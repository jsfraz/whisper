import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:shept_openapi_client_dart/api.dart';

import 'cache_utils.dart';
import 'media_utils.dart';
import 'singleton.dart';
import 'utils.dart';

/// One recorded upload session of an unfinished attachment.
class _Record {
  final String id;
  final int totalSize;
  final Uint8List key;
  final Uint8List nonce;

  const _Record(this.id, this.totalSize, this.key, this.nonce);
}

/// Resumable upload of one attachment.
///
/// The server appends one chunk per request and reports the offset it holds, so
/// a connection that dies halfway costs only the bytes since the last accepted
/// chunk. While an upload is unfinished its session is recorded together with
/// the transport key and nonce, which is what lets a retry continue it (even
/// after a restart) instead of uploading the whole ciphertext again: the same
/// key and nonce reproduce the same bytes.
class MediaUploader {
  MediaUploader._();

  /// Upload the plaintext [bytes] of one attachment for [receiverId] and return
  /// the media id and the transport encryption used.
  ///
  /// [messageKey] and [index] identify the attachment of a stored message; when
  /// a session is recorded for that pair it is resumed.
  ///
  /// shortcut: the plaintext and its whole ciphertext are held in memory
  /// together, so the 100 MiB cap can still exhaust a low-end phone; upgrade by
  /// encrypting and sending one chunk at a time.
  static Future<(String, TransportEncryption)> upload(
    Uint8List bytes, {
    required String receiverId,
    String? messageKey,
    int index = 0,
  }) async {
    final recordKey = messageKey == null ? null : '$messageKey|$index';
    final totalSize = bytes.length + MediaUtils.transportOverheadBytes;
    TransportEncryption? transport;
    String? uploadId;
    var received = 0;

    final record = await _read(recordKey);
    if (record != null && record.totalSize == totalSize) {
      transport = await MediaUtils.encryptForTransport(bytes,
          key: record.key, nonce: record.nonce);
      final state = await _state(record.id);
      if (state != null && state.totalSize == totalSize) {
        uploadId = record.id;
        received = state.received;
      }
    }

    transport ??= await MediaUtils.encryptForTransport(bytes);
    if (uploadId == null) {
      final session = await Utils.callApi(
        () => Singleton().mediaApi.createMediaUpload(
              createMediaUploadInput: CreateMediaUploadInput(
                receiverId: receiverId,
                totalSize: totalSize,
              ),
            ),
        rethrowErr: true,
      );
      if (session == null) {
        throw Exception('mediaUploadFailed'.tr());
      }
      uploadId = session.id;
      received = session.received;
      if (recordKey != null) {
        await CacheUtils.setPendingUpload(
            recordKey,
            jsonEncode({
              'id': uploadId,
              'totalSize': totalSize,
              'key': base64Encode(transport.key),
              'nonce': base64Encode(transport.nonce),
              'receiverId': receiverId,
            }));
      }
    }

    final blob = transport.blob;
    while (received < blob.length) {
      final start = received;
      final end = min(start + MediaUtils.uploadChunkBytes, blob.length);
      final chunk = http.MultipartFile.fromBytes(
          'chunk', blob.sublist(start, end),
          filename: 'chunk.bin');
      try {
        final session = await Utils.callApi(
          () => Singleton().mediaApi.uploadMediaChunk(uploadId!, start, chunk),
          rethrowErr: true,
          showError: false,
        );
        received = session == null ? end : session.received;
      } on ApiException catch (e) {
        if (e.code != 409) {
          rethrow;
        }
        // 409 is the resume path: the server holds a different offset.
        final state = await _state(uploadId);
        if (state == null || state.totalSize != totalSize) {
          // The session expired or belongs to another file: start over.
          if (recordKey != null) {
            await CacheUtils.removePendingUpload(recordKey);
          }
          return upload(bytes,
              receiverId: receiverId, messageKey: messageKey, index: index);
        }
        received = state.received;
      }
    }

    final completed = await Utils.callApi(
      () => Singleton().mediaApi.completeMediaUpload(uploadId!),
      rethrowErr: true,
    );
    if (completed == null) {
      throw Exception('mediaUploadFailed'.tr());
    }
    if (recordKey != null) {
      await CacheUtils.removePendingUpload(recordKey);
    }
    return (completed.id, transport);
  }

  /// The recorded session of one attachment, or null.
  static Future<_Record?> _read(String? recordKey) async {
    if (recordKey == null) {
      return null;
    }
    final raw = await CacheUtils.getPendingUpload(recordKey);
    if (raw == null) {
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _Record(
        json['id'] as String,
        (json['totalSize'] as num).toInt(),
        base64Decode(json['key'] as String),
        base64Decode(json['nonce'] as String),
      );
    } catch (_) {
      await CacheUtils.removePendingUpload(recordKey);
      return null;
    }
  }

  /// The server's view of one session, or null when it is gone.
  static Future<ModelsMediaUploadSessionResponse?> _state(
      String uploadId) async {
    try {
      return await Utils.callApi<ModelsMediaUploadSessionResponse?>(
        () => Singleton().mediaApi.getMediaUpload(uploadId),
        rethrowErr: true,
        showError: false,
      );
    } on ApiException catch (e) {
      if (e.code == 404) {
        return null;
      }
      rethrow;
    }
  }
}
