import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:easy_localization/easy_localization.dart';
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
/// `sent` afterwards, so the message is visible immediately and a failure leaves
/// a visible failed state instead of a silent loss.
class ChatSender {
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
      final data = await CryptoUtils.encryptMessageData(utf8.encode(text),
          bu.CryptoUtils.rsaPublicKeyFromPem(recipient.publicKey));
      Singleton().wsClient.sendMessage(WsMessage.privateMessage(
          NewPrivateMessage(recipient.id, data['encryptedData']!,
              data['encryptedKey']!, data['nonce']!, data['mac']!)));
      await _markSent(recipient.id, message);
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
      final envelope = MediaUtils.buildMediaEnvelope(reference, caption);
      await _sendEnvelope(recipient, envelope);
      await CacheUtils.updateStoredMessage(recipient.id, message, (stored) {
        stored.mediaId = reference.mediaId;
        stored.sendStatus = SendStatus.sent;
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

      final envelope = MediaUtils.buildAlbumEnvelope(references, caption);
      await _sendEnvelope(recipient, envelope);
      await CacheUtils.updateStoredMessage(recipient.id, message, (stored) {
        final items = stored.album;
        for (var i = 0; i < items.length && i < references.length; i++) {
          items[i].mediaId = references[i].mediaId;
        }
        stored.setAlbum(items);
        stored.sendStatus = SendStatus.sent;
      });
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return await _fail(recipient.id, message);
    }
  }

  /// Upload one already transport-encrypted attachment and build its reference.
  static Future<MediaReference?> _uploadReference(
      User recipient,
      MediaType type,
      Uint8List key,
      Uint8List blob,
      {int? width,
      int? height,
      int? durationMs,
      String? fileName}) async {
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
      User recipient, Uint8List envelope) async {
    final data = await CryptoUtils.encryptMessageData(
        envelope, bu.CryptoUtils.rsaPublicKeyFromPem(recipient.publicKey));
    Singleton().wsClient.sendMessage(WsMessage.privateMessage(
        NewPrivateMessage(recipient.id, data['encryptedData']!,
            data['encryptedKey']!, data['nonce']!, data['mac']!)));
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

  static Future<void> _markSent(String userId, PrivateMessage message) =>
      CacheUtils.updateStoredMessage(userId, message, (stored) {
        stored.sendStatus = SendStatus.sent;
      });

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
  }
}
