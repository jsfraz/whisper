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

/// Sends messages to an arbitrary recipient. Shared by the chat page and the
/// forward page so both use one encrypted, persisted send path.
///
/// Each method reports its own errors with a toast and returns whether the
/// message was sent.
class ChatSender {
  /// Send a text message to [recipient].
  static Future<bool> sendText(User recipient, String text) async {
    try {
      await Utils.wsConnect();
      if (!Singleton().wsClient.isConnected) {
        Fluttertoast.showToast(
            msg: 'wsOffline'.tr(), backgroundColor: Colors.red);
        return false;
      }
      final data = await CryptoUtils.encryptMessageData(utf8.encode(text),
          bu.CryptoUtils.rsaPublicKeyFromPem(recipient.publicKey));
      final sentAt = Singleton().wsClient.sendMessage(WsMessage.privateMessage(
          NewPrivateMessage(recipient.id, data['encryptedData']!,
              data['encryptedKey']!, data['nonce']!, data['mac']!)));
      await _persist(recipient, [
        PrivateMessage(Singleton().profile.user.id, text, sentAt, sentAt, true)
      ]);
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return false;
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
    try {
      await Utils.wsConnect();
      if (!Singleton().wsClient.isConnected) {
        Fluttertoast.showToast(
            msg: 'wsOffline'.tr(), backgroundColor: Colors.red);
        return false;
      }

      // Transport encryption with an ephemeral per-file key.
      final transport = await MediaUtils.encryptForTransport(bytes);

      // Upload the ciphertext over HTTP.
      final uploadResponse = await Utils.callApi(
        () => Singleton().mediaApi.uploadMedia(
              http.MultipartFile.fromBytes('file', transport.blob,
                  filename: 'media.bin'),
              recipient.id,
            ),
        rethrowErr: true,
      );
      if (uploadResponse == null) {
        Fluttertoast.showToast(
            msg: 'mediaUploadFailed'.tr(), backgroundColor: Colors.red);
        return false;
      }
      final mediaId = uploadResponse.id;

      // Build the encrypted reference and wrap it in the message envelope.
      final reference = MediaReference(
        mediaId,
        transport.key,
        type,
        transport.blob.length,
        width: width,
        height: height,
        durationMs: durationMs,
        fileName: fileName,
      );
      final envelope = MediaUtils.buildMediaEnvelope(reference, caption);

      // E2E-encrypt the envelope for the recipient.
      final data = await CryptoUtils.encryptMessageData(
          envelope, bu.CryptoUtils.rsaPublicKeyFromPem(recipient.publicKey));

      // Send over the WebSocket.
      final sentAt = Singleton().wsClient.sendMessage(WsMessage.privateMessage(
          NewPrivateMessage(recipient.id, data['encryptedData']!,
              data['encryptedKey']!, data['nonce']!, data['mac']!)));

      // Store the original media encrypted-at-rest for our own bubble.
      final localPath = await MediaUtils.encryptAtRest(bytes);

      await _persist(recipient, [
        PrivateMessage(
          Singleton().profile.user.id,
          caption,
          sentAt,
          sentAt,
          true,
          mediaId: mediaId,
          mediaTypeStr: type.name,
          localPath: localPath,
          mediaSize: bytes.length,
          width: width,
          height: height,
          durationMs: durationMs,
          downloadStatus: MediaDownloadStatus.ready,
          fileName: fileName,
        )
      ]);
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      return false;
    }
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
