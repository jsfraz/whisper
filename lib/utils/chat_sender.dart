import 'dart:convert';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shept_websocket_client_dart/models/media_reference.dart';
import 'package:shept_websocket_client_dart/models/media_type.dart';
import 'package:shept_websocket_client_dart/models/new_private_message.dart';
import 'package:shept_websocket_client_dart/models/ws_message.dart';

import '../models/private_message.dart';
import '../models/user.dart';
import 'cache_utils.dart';
import 'crypto_utils.dart';
import 'media_upload.dart';
import 'media_utils.dart';
import 'message_notifier.dart';
import 'singleton.dart';
import 'text_envelope.dart';
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

  /// Send a text message to [recipient], optionally quoting [reply] or marked
  /// as forwarded.
  static Future<bool> sendText(User recipient, String text,
      {ReplyRef? reply, bool forwarded = false}) async {
    final now = DateTime.now();
    final ttl = await _ttlFor(recipient);
    final message = PrivateMessage(
        Singleton().profile.user.id, text, now, now, true,
        sendStatus: SendStatus.sending,
        forwarded: forwarded,
        expiresAt: ttl > 0 ? now.add(Duration(seconds: ttl)) : null)
      ..setReplyTo(reply);
    try {
      await _persist(recipient, [message]);
      if (!await _ensureConnected()) {
        return await _fail(recipient.id, message);
      }
      await _sendText(recipient, message, ttl: ttl);
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
      String? fileName,
      List<int>? waveform,
      bool videoNote = false,
      bool forwarded = false,
      bool viewOnce = false}) async {
    if (!MediaUtils.uploadFits(bytes.length)) {
      _toastTooLarge();
      return false;
    }
    // Store the original media encrypted-at-rest first, so the bubble can show
    // the content while the upload is still running.
    final localPath = await MediaUtils.encryptAtRest(bytes);
    final now = DateTime.now();
    // A view-once attachment lives a day whatever the chat timer says; anything
    // else follows the agreed timer.
    final ttl = viewOnce ? viewOnceTtlSeconds : await _ttlFor(recipient);
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
      forwarded: forwarded,
      viewOnce: viewOnce,
      expiresAt: ttl > 0 ? now.add(Duration(seconds: ttl)) : null,
    );
    try {
      await _persist(recipient, [message]);
      if (videoNote) {
        // The reference only exists after the upload, but the bubble has to know
        // it is a round note from the first frame: mark it now, the finished
        // reference overwrites this below.
        await CacheUtils.updateStoredMessage(recipient.id, message, (stored) {
          stored.mediaRefJson = jsonEncode({'videoNote': true});
        });
      }
      if (!await _ensureConnected()) {
        return await _fail(recipient.id, message);
      }
      final reference = await _uploadReference(recipient, type, bytes,
          messageKey: CacheUtils.messageKey(recipient.id, message.sentAt),
          width: width,
          height: height,
          durationMs: durationMs,
          fileName: fileName,
          waveform: waveform,
          videoNote: videoNote);
      if (reference == null) {
        return await _fail(recipient.id, message);
      }
      _outgoingReferences[CacheUtils.messageKey(recipient.id, message.sentAt)] =
          [reference];
      final envelope = MediaUtils.buildMediaEnvelope(reference, caption,
          forwarded: forwarded, viewOnce: viewOnce);
      await _sendEnvelope(recipient, envelope, message.sentAt, ttlSeconds: ttl);
      await CacheUtils.updateStoredMessage(recipient.id, message, (stored) {
        stored.mediaId = reference.mediaId;
        // Keep the reference (with its transport key) so the caption can be
        // edited later without the original upload.
        stored.mediaRefJson = jsonEncode(reference.toJson());
        // The sender never keeps the content of a view-once attachment: one
        // open belongs to the recipient, so the local copy goes right away.
        if (viewOnce) {
          stored.localPath = null;
        }
      });
      if (viewOnce) {
        await MediaUtils.deleteLocalFile(localPath);
      }
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
      {String caption = '',
      bool forwarded = false,
      bool viewOnce = false}) async {
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
    // A view-once album follows the same one-day life as a single attachment.
    final ttl = viewOnce ? viewOnceTtlSeconds : await _ttlFor(recipient);
    final message = PrivateMessage(
      Singleton().profile.user.id,
      caption,
      now,
      now,
      true,
      downloadStatus: MediaDownloadStatus.ready,
      sendStatus: SendStatus.sending,
      forwarded: forwarded,
      viewOnce: viewOnce,
      expiresAt: ttl > 0 ? now.add(Duration(seconds: ttl)) : null,
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
      final messageKey = CacheUtils.messageKey(recipient.id, message.sentAt);
      for (var i = 0; i < attachments.length; i++) {
        final attachment = attachments[i];
        final reference = await _uploadReference(
            recipient, attachment.type, attachment.bytes,
            messageKey: messageKey,
            index: i,
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
      final envelope = MediaUtils.buildAlbumEnvelope(references, caption,
          forwarded: forwarded, viewOnce: viewOnce);
      await _sendEnvelope(recipient, envelope, message.sentAt, ttlSeconds: ttl);
      await CacheUtils.updateStoredMessage(recipient.id, message, (stored) {
        final items = stored.album;
        for (var i = 0; i < items.length && i < references.length; i++) {
          items[i].mediaId = references[i].mediaId;
          items[i].keyB64 = base64Encode(references[i].key);
          // A view-once album keeps no copy on the sending side.
          if (viewOnce) {
            items[i].localPath = null;
          }
        }
        stored.setAlbum(items);
      });
      if (viewOnce) {
        for (final path in localPaths) {
          await MediaUtils.deleteLocalFile(path);
        }
      }
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return await _fail(recipient.id, message);
    }
  }

  /// Media references of an already stored message, for re-encrypting it with a
  /// new caption. Prefers what the row kept, then the upload cache, and only
  /// re-uploads the local copies when neither has it (a message from a build
  /// that did not keep the key yet).
  static Future<List<MediaReference>?> mediaReferencesFor(
      User recipient, PrivateMessage message) async {
    final kept = message.mediaReferences;
    if (kept != null && kept.isNotEmpty) {
      return kept;
    }
    final cached = _outgoingReferences[
        CacheUtils.messageKey(recipient.id, message.sentAt)];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    return _uploadLocalCopies(recipient, message);
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
  static Future<void> confirmSent(String receiverId, DateTime sentAt,
      {String? id}) async {
    await CacheUtils.markMessageSent(receiverId, sentAt, id: id);
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
        ? MediaUtils.buildAlbumEnvelope(references, message.message,
            forwarded: message.forwarded)
        : MediaUtils.buildMediaEnvelope(references.first, message.message,
            forwarded: message.forwarded);
    await _sendEnvelope(recipient, envelope, message.sentAt);
  }

  /// Re-upload the attachments stored on this device. Null when a local copy
  /// is missing or the upload failed.
  static Future<List<MediaReference>?> _uploadLocalCopies(
      User recipient, PrivateMessage message) async {
    final messageKey = CacheUtils.messageKey(recipient.id, message.sentAt);
    Future<MediaReference?> upload(String? path, MediaType? type, int index,
        {int? width,
        int? height,
        int? durationMs,
        String? fileName,
        List<int>? waveform}) async {
      if (path == null || type == null) {
        return null;
      }
      final bytes = await MediaUtils.decryptAtRest(path);
      if (!MediaUtils.uploadFits(bytes.length)) {
        _toastTooLarge();
        return null;
      }
      return _uploadReference(recipient, type, bytes,
          messageKey: messageKey,
          index: index,
          width: width,
          height: height,
          durationMs: durationMs,
          fileName: fileName,
          waveform: waveform,
          // Only a single video is ever a note; the stored reference says so.
          videoNote: message.mediaReferences?.first.videoNote ?? false);
    }

    final references = <MediaReference>[];
    if (message.isAlbum) {
      for (var i = 0; i < message.album.length; i++) {
        final item = message.album[i];
        final reference = await upload(item.localPath, item.mediaType, i,
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
      final reference = await upload(message.localPath, message.mediaType, 0,
          width: message.width,
          height: message.height,
          durationMs: message.durationMs,
          fileName: message.fileName,
          // A voice message keeps its recorded shape across a retry.
          waveform: message.mediaReferences?.first.waveform);
      if (reference == null) {
        return null;
      }
      references.add(reference);
    }
    return references;
  }

  /// Encrypt [message] for [recipient] and hand it to the WebSocket. The
  /// original timestamp is kept so a resend maps onto the same server entry.
  static Future<void> _sendText(User recipient, PrivateMessage message,
      {int ttl = 0, Uint8List? plaintextOverride}) async {
    // A reply needs the quote next to the body; everything else stays raw text
    // so an older client can still read it.
    final reply = message.replyTo;
    final plaintext = plaintextOverride ??
        (reply == null && !message.forwarded
            ? utf8.encode(message.message)
            : buildTextEnvelope(message.message, reply,
                forwarded: message.forwarded));
    final data = await CryptoUtils.encryptMessageData(
        plaintext, bu.CryptoUtils.rsaPublicKeyFromPem(recipient.publicKey));
    Singleton().wsClient.sendMessage(WsMessage.privateMessage(NewPrivateMessage(
        recipient.id,
        data['encryptedData']!,
        data['encryptedKey']!,
        data['nonce']!,
        data['mac']!,
        sentAt: message.sentAt,
        ttlSeconds: ttl > 0 ? ttl : null)));
  }

  /// Upload one attachment and build its reference.
  ///
  /// Returns null when the upload failed. The recorded session is kept, so the
  /// retry of that message continues where the connection broke instead of
  /// starting from zero.
  static Future<MediaReference?> _uploadReference(
    User recipient,
    MediaType type,
    Uint8List bytes, {
    required String messageKey,
    int index = 0,
    int? width,
    int? height,
    int? durationMs,
    String? fileName,
    List<int>? waveform,
    bool videoNote = false,
  }) async {
    try {
      final (mediaId, transport) = await MediaUploader.upload(
        bytes,
        receiverId: recipient.id,
        messageKey: messageKey,
        index: index,
      );
      return MediaReference(
        mediaId,
        transport.key,
        type,
        transport.blob.length,
        width: width,
        height: height,
        durationMs: durationMs,
        fileName: fileName,
        waveform: waveform,
        videoNote: videoNote,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('media upload failed: $e');
      }
      Fluttertoast.showToast(
          msg: 'mediaUploadFailed'.tr(), backgroundColor: Colors.red);
      return null;
    }
  }

  /// E2E-encrypt [envelope] for [recipient] and hand it to the WebSocket.
  static Future<void> _sendEnvelope(
      User recipient, Uint8List envelope, DateTime sentAt,
      {int ttlSeconds = 0}) async {
    final data = await CryptoUtils.encryptMessageData(
        envelope, bu.CryptoUtils.rsaPublicKeyFromPem(recipient.publicKey));
    Singleton().wsClient.sendMessage(WsMessage.privateMessage(NewPrivateMessage(
        recipient.id,
        data['encryptedData']!,
        data['encryptedKey']!,
        data['nonce']!,
        data['mac']!,
        sentAt: sentAt,
        ttlSeconds: ttlSeconds > 0 ? ttlSeconds : null)));
  }

  /// Life of a view-once attachment: one day, whether or not the chat has a
  /// disappearing timer.
  static const int viewOnceTtlSeconds = 86400;

  /// Sends a static location: an ordinary text message whose envelope also
  /// carries the coordinates. The server sees only the ciphertext.
  static Future<bool> sendLocation(User recipient, double lat, double lng,
      {double? accuracy, String? label, bool viewOnce = false}) async {
    final now = DateTime.now();
    final ttl = viewOnce ? viewOnceTtlSeconds : await _ttlFor(recipient);
    final location = LocationRef(lat, lng, accuracy: accuracy, label: label);
    final message = PrivateMessage(
        Singleton().profile.user.id, location.body, now, now, true,
        sendStatus: SendStatus.sending,
        locationJson: jsonEncode(location.toJson()),
        viewOnce: viewOnce,
        expiresAt: ttl > 0 ? now.add(Duration(seconds: ttl)) : null);
    try {
      await _persist(recipient, [message]);
      if (!await _ensureConnected()) {
        return await _fail(recipient.id, message);
      }
      await _sendText(recipient, message,
          ttl: ttl,
          plaintextOverride: buildTextEnvelope(location.body, null,
              location: location, viewOnce: viewOnce));
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return await _fail(recipient.id, message);
    }
  }

  /// The agreed disappearing timer of one chat in seconds, 0 when off.
  static Future<int> _ttlFor(User recipient) =>
      CacheUtils.getDisappearingSeconds(recipient.id);

  /// Sends one step of the disappearing-message agreement. The message is
  /// archived and encrypted like any other, so the other device and a device
  /// that syncs later all see the same state.
  static Future<bool> sendSystem(
      User recipient, String state, int seconds) async {
    final now = DateTime.now();
    final message = PrivateMessage(
        Singleton().profile.user.id, '', now, now, true,
        sendStatus: SendStatus.sending,
        systemState: state,
        systemSeconds: seconds);
    try {
      await _persist(recipient, [message]);
      if (!await _ensureConnected()) {
        return await _fail(recipient.id, message);
      }
      await _sendEnvelope(recipient, buildSystemEnvelope(state, seconds), now);
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return await _fail(recipient.id, message);
    }
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
