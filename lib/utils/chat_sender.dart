import 'dart:convert';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import 'package:whisper_websocket_client_dart/models/new_private_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_message.dart';

import '../models/private_message.dart';
import '../models/user.dart';
import 'cache_utils.dart';
import 'crypto_utils.dart';
import 'media_utils.dart';
import 'message_notifier.dart';
import 'singleton.dart';
import 'utils.dart';

/// One attachment of an outgoing album (or a single media message).
class OutgoingAttachment {
  final MediaType type;
  final Uint8List bytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? fileName;

  const OutgoingAttachment({
    required this.type,
    required this.bytes,
    this.width,
    this.height,
    this.durationMs,
    this.fileName,
  });
}

/// Sends messages to an arbitrary recipient. Shared by the chat page and the
/// forward page so both use one encrypted, persisted send path.
///
/// The bubble is stored as `sending` before anything goes out and flipped to
/// `sent` only when the server acknowledges the message. Without an ack the
/// message stays pending and is resent on the next connect, so a lost frame is
/// visible instead of silent.
class ChatSender {
  /// Transport references of media messages sent in this session, keyed by
  /// [CacheUtils.messageKey]. Needed to resend a media message whose ack was
  /// lost; the transport key is never persisted, so after a restart such a
  /// message cannot be resent.
  ///
  /// shortcut: resending media only works in the session that uploaded it,
  /// upgrade by persisting the transport key inside the encrypted profile box.
  static final Map<String, List<MediaReference>> _outgoingReferences = {};

  /// Send a text message to [recipient].
  static Future<bool> sendText(User recipient, String text) async {
    final now = DateTime.now();
    final message = PrivateMessage(
        Singleton().profile.user.id, text, now, now, true,
        sendStatus: SendStatus.sending);
    try {
      await _persist(recipient, [message]);
      if (!await _ensureConnected()) {
        return await _fail(recipient.id, message);
      }
      await _sendText(recipient, message);
      // No ack yet: the message stays `sending` until the server confirms.
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return await _fail(recipient.id, message);
    }
  }

  /// Send [bytes] as a media attachment of [type] to [recipient]. The caller
  /// supplies the probed metadata so `null` there is meaningful.
  static Future<bool> sendMedia(User recipient, MediaType type, Uint8List bytes,
      {String caption = '',
      int? width,
      int? height,
      int? durationMs,
      String? fileName}) async {
    if (!MediaUtils.uploadFits(bytes.length)) {
      _toastTooLarge();
      return false;
    }
    // Store the original media encrypted-at-rest first, so the bubble can show
    // the content while the upload is still running.
    final localPath = await MediaUtils.encryptAtRest(bytes);
    final now = DateTime.now();
    final message = PrivateMessage(
      Singleton().profile.user.id,
      caption,
      now,
      now,
      true,
      mediaTypeStr: type.name,
      localPath: localPath,
      mediaSize: bytes.length,
      width: width,
      height: height,
      durationMs: durationMs,
      downloadStatus: MediaDownloadStatus.ready,
      fileName: fileName,
      sendStatus: SendStatus.sending,
    );
    try {
      await _persist(recipient, [message]);
      if (!await _ensureConnected()) {
        return await _fail(recipient.id, message);
      }
      final transport = await MediaUtils.encryptForTransport(bytes);
      final reference = await _uploadReference(
          recipient, type, transport.key, transport.blob,
          width: width,
          height: height,
          durationMs: durationMs,
          fileName: fileName);
      if (reference == null) {
        return await _fail(recipient.id, message);
      }
      _outgoingReferences[CacheUtils.messageKey(recipient.id, message.sentAt)] =
          [reference];
      final envelope = MediaUtils.buildMediaEnvelope(reference, caption);
      await _sendEnvelope(recipient, envelope, message.sentAt);
      await CacheUtils.updateStoredMessage(recipient.id, message, (stored) {
        stored.mediaId = reference.mediaId;
      });
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return await _fail(recipient.id, message);
    }
  }

  /// Send several attachments as one album message: one bubble, one encrypted
  /// envelope carrying all references, one WebSocket message.
  static Future<bool> sendAlbum(
      User recipient, List<OutgoingAttachment> attachments,
      {String caption = ''}) async {
    if (attachments.isEmpty) {
      return false;
    }
    for (final attachment in attachments) {
      if (!MediaUtils.uploadFits(attachment.bytes.length)) {
        _toastTooLarge();
        return false;
      }
    }

    // Local copies first: the album bubble is visible while uploading.
    final localPaths = <String>[];
    for (final attachment in attachments) {
      localPaths.add(await MediaUtils.encryptAtRest(attachment.bytes));
    }
    final now = DateTime.now();
    final message = PrivateMessage(
      Singleton().profile.user.id,
      caption,
      now,
      now,
      true,
      downloadStatus: MediaDownloadStatus.ready,
      sendStatus: SendStatus.sending,
    );
    message.setAlbum([
      for (var i = 0; i < attachments.length; i++)
        AlbumItem(
          mediaId: '',
          type: attachments[i].type.name,
          size: attachments[i].bytes.length,
          width: attachments[i].width,
          height: attachments[i].height,
          durationMs: attachments[i].durationMs,
          fileName: attachments[i].fileName,
          localPath: localPaths[i],
          status: MediaDownloadStatus.ready,
        )
    ]);

    try {
      await _persist(recipient, [message]);
      if (!await _ensureConnected()) {
        return await _fail(recipient.id, message);
      }

      // The server takes one file per request, so the album is N uploads.
      final references = <MediaReference>[];
      for (final attachment in attachments) {
        final transport =
            await MediaUtils.encryptForTransport(attachment.bytes);
        final reference = await _uploadReference(
            recipient, attachment.type, transport.key, transport.blob,
            width: attachment.width,
            height: attachment.height,
            durationMs: attachment.durationMs,
            fileName: attachment.fileName);
        if (reference == null) {
          return await _fail(recipient.id, message);
        }
        references.add(reference);
      }

      _outgoingReferences[CacheUtils.messageKey(recipient.id, message.sentAt)] =
          references;
      final envelope = MediaUtils.buildAlbumEnvelope(references, caption);
      await _sendEnvelope(recipient, envelope, message.sentAt);
      await CacheUtils.updateStoredMessage(recipient.id, message, (stored) {
        final items = stored.album;
        for (var i = 0; i < items.length && i < references.length; i++) {
          items[i].mediaId = references[i].mediaId;
        }
        stored.setAlbum(items);
      });
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return await _fail(recipient.id, message);
    }
  }

  /// Resend every message that never received a delivery ack.
  ///
  /// Called after a WebSocket reconnect: the server deduplicates by
  /// (receiver, sentAt), so a message that did arrive is not delivered twice.
  static Future<void> resendPending() async {
    if (!Singleton().wsClient.isConnected) {
      return;
    }
    final pending = await CacheUtils.getPendingSends();
    for (final entry in pending.entries) {
      final recipient = await CacheUtils.getUserById(entry.key);
      if (recipient == null || recipient.publicKey.isEmpty) {
        continue;
      }
      for (final message in entry.value) {
        try {
          final fresh = await _withAcceptedSentAt(entry.key, message);
          if (fresh != null) {
            await _sendStored(recipient, fresh);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('resend failed: $e');
          }
        }
      }
    }
  }

  /// Resend a single stored message after its send failed (bubble long-press).
  ///
  /// The original timestamp is kept while the server still accepts it, so the
  /// server deduplicates against the failed attempt and the bubble stays put.
  static Future<bool> resend(String receiverId, PrivateMessage message) async {
    final recipient = await CacheUtils.getUserById(receiverId);
    if (recipient == null || recipient.publicKey.isEmpty) {
      Fluttertoast.showToast(
          msg: 'userNotFound'.tr(), backgroundColor: Colors.red);
      return false;
    }
    final fresh = await _withAcceptedSentAt(receiverId, message);
    if (fresh == null) {
      return false;
    }
    await CacheUtils.updateStoredMessage(receiverId, fresh, (stored) {
      stored.sendStatus = SendStatus.sending;
    });
    fresh.sendStatus = SendStatus.sending;
    await CacheUtils.addPendingSend(receiverId, fresh.sentAt);
    MessageNotifier().notify();
    try {
      if (!await _ensureConnected()) {
        return await _fail(receiverId, fresh);
      }
      await _sendStored(recipient, fresh);
      // No ack yet: the message stays `sending` until the server confirms.
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return await _fail(receiverId, fresh);
    }
  }

  /// How old a client timestamp may be and still be accepted by the server
  /// (`models.MaxSentAtSkew`, minus a minute for clock drift between the two).
  static const Duration _maxSentAtAge = Duration(minutes: 4);

  /// The stored message to send again, with a timestamp the server will take.
  ///
  /// Returns null when the message is gone. A timestamp older than the server
  /// accepts is replaced with now, which moves the bubble to the end of the
  /// chat.
  ///
  /// shortcut: a retry that late cannot dedupe against the first attempt, so a
  /// message that did arrive with a lost ack is delivered twice; upgrade by
  /// keeping the server-side dedup key separate from the display time.
  static Future<PrivateMessage?> _withAcceptedSentAt(
      String receiverId, PrivateMessage message) async {
    if (DateTime.now().difference(message.sentAt) <= _maxSentAtAge) {
      return message;
    }
    final moved = await CacheUtils.retimestampMessage(receiverId, message);
    if (moved != null) {
      // The old marker is gone with the old key; keep the new one watchable.
      await CacheUtils.addPendingSend(receiverId, moved.sentAt);
    }
    return moved;
  }

  /// Mark a message as sent after the server acknowledged it.
  static Future<void> confirmSent(String receiverId, DateTime sentAt) async {
    await CacheUtils.markMessageSent(receiverId, sentAt);
    _outgoingReferences.remove(CacheUtils.messageKey(receiverId, sentAt));
    MessageNotifier().notify();
  }

  /// Hand an already stored message to the WebSocket again.
  ///
  /// Media needs its transport references; when this session no longer holds
  /// them (an offline send, or a restart), the copies on disk are re-encrypted
  /// and uploaded once more.
  static Future<void> _sendStored(
      User recipient, PrivateMessage message) async {
    if (!message.isMedia) {
      await _sendText(recipient, message);
      return;
    }
    final key = CacheUtils.messageKey(recipient.id, message.sentAt);
    final references = _outgoingReferences[key] ??
        await _uploadLocalCopies(recipient, message);
    if (references == null || references.isEmpty) {
      throw Exception('mediaUploadFailed'.tr());
    }
    _outgoingReferences[key] = references;
    final envelope = message.isAlbum
        ? MediaUtils.buildAlbumEnvelope(references, message.message)
        : MediaUtils.buildMediaEnvelope(references.first, message.message);
    await _sendEnvelope(recipient, envelope, message.sentAt);
  }

  /// Re-upload the attachments stored on this device. Null when a local copy
  /// is missing or the upload failed.
  static Future<List<MediaReference>?> _uploadLocalCopies(
      User recipient, PrivateMessage message) async {
    Future<MediaReference?> upload(String? path, MediaType? type,
        {int? width, int? height, int? durationMs, String? fileName}) async {
      if (path == null || type == null) {
        return null;
      }
      final bytes = await MediaUtils.decryptAtRest(path);
      if (!MediaUtils.uploadFits(bytes.length)) {
        _toastTooLarge();
        return null;
      }
      final transport = await MediaUtils.encryptForTransport(bytes);
      return _uploadReference(recipient, type, transport.key, transport.blob,
          width: width,
          height: height,
          durationMs: durationMs,
          fileName: fileName);
    }

    final references = <MediaReference>[];
    if (message.isAlbum) {
      for (final item in message.album) {
        final reference = await upload(item.localPath, item.mediaType,
            width: item.width,
            height: item.height,
            durationMs: item.durationMs,
            fileName: item.fileName);
        if (reference == null) {
          return null;
        }
        references.add(reference);
      }
    } else {
      final reference = await upload(message.localPath, message.mediaType,
          width: message.width,
          height: message.height,
          durationMs: message.durationMs,
          fileName: message.fileName);
      if (reference == null) {
        return null;
      }
      references.add(reference);
    }
    return references;
  }

  /// Encrypt [message] for [recipient] and hand it to the WebSocket. The
  /// original timestamp is kept so a resend maps onto the same server entry.
  static Future<void> _sendText(User recipient, PrivateMessage message) async {
    final data = await CryptoUtils.encryptMessageData(
        utf8.encode(message.message),
        bu.CryptoUtils.rsaPublicKeyFromPem(recipient.publicKey));
    Singleton().wsClient.sendMessage(WsMessage.privateMessage(NewPrivateMessage(
        recipient.id,
        data['encryptedData']!,
        data['encryptedKey']!,
        data['nonce']!,
        data['mac']!,
        sentAt: message.sentAt)));
  }

  /// Upload one already transport-encrypted attachment and build its reference.
  static Future<MediaReference?> _uploadReference(
    User recipient,
    MediaType type,
    Uint8List key,
    Uint8List blob, {
    int? width,
    int? height,
    int? durationMs,
    String? fileName,
  }) async {
    final uploadResponse = await Utils.callApi(
      () => Singleton().mediaApi.uploadMedia(
            http.MultipartFile.fromBytes('file', blob, filename: 'media.bin'),
            recipient.id,
          ),
      rethrowErr: true,
    );
    if (uploadResponse == null) {
      Fluttertoast.showToast(
          msg: 'mediaUploadFailed'.tr(), backgroundColor: Colors.red);
      return null;
    }
    return MediaReference(
      uploadResponse.id,
      key,
      type,
      blob.length,
      width: width,
      height: height,
      durationMs: durationMs,
      fileName: fileName,
    );
  }

  /// E2E-encrypt [envelope] for [recipient] and hand it to the WebSocket.
  static Future<void> _sendEnvelope(
      User recipient, Uint8List envelope, DateTime sentAt) async {
    final data = await CryptoUtils.encryptMessageData(
        envelope, bu.CryptoUtils.rsaPublicKeyFromPem(recipient.publicKey));
    Singleton().wsClient.sendMessage(WsMessage.privateMessage(NewPrivateMessage(
        recipient.id,
        data['encryptedData']!,
        data['encryptedKey']!,
        data['nonce']!,
        data['mac']!,
        sentAt: sentAt)));
  }

  /// Connect the WebSocket if needed; toasts and reports false when offline.
  static Future<bool> _ensureConnected() async {
    await Utils.wsConnect();
    if (Singleton().wsClient.isConnected) {
      return true;
    }
    Fluttertoast.showToast(msg: 'wsOffline'.tr(), backgroundColor: Colors.red);
    return false;
  }

  static void _toastTooLarge() {
    Fluttertoast.showToast(
        msg:
            '${'fileTooLarge'.tr()} ${MediaUtils.formatBytes(MediaUtils.maxUploadBytes)}',
        backgroundColor: Colors.red);
  }

  /// Mark a persisted message as failed and report the failure.
  static Future<bool> _fail(String userId, PrivateMessage message) async {
    await CacheUtils.updateStoredMessage(userId, message, (stored) {
      stored.sendStatus = SendStatus.failed;
    });
    return false;
  }

  /// Store the recipient and the sent message in the local cache.
  static Future<void> _persist(
      User recipient, List<PrivateMessage> messages) async {
    if (recipient.publicKey != '' &&
        recipient.username != '' &&
        !recipient.isInBox) {
      await CacheUtils.addUser(recipient);
    }
    await MessageNotifier().addMessages(recipient.id, messages);
    for (final message in messages) {
      await CacheUtils.addPendingSend(recipient.id, message.sentAt);
    }
  }
}
