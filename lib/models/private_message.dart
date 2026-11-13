import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:hive/hive.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import '../utils/singleton.dart';

part 'private_message.g.dart';

/// Download status of a media attachment stored locally.
class MediaDownloadStatus {
  /// Not yet downloaded/decrypted (recipient side, in progress).
  static const int pending = 0;

  /// Downloaded, decrypted and stored encrypted-at-rest locally.
  static const int ready = 1;

  /// Download or decryption failed; can be retried.
  static const int failed = 2;
}

/// Outbound send state, shown as an icon in the bubble.
class SendStatus {
  /// Written to the cache, not yet handed to the WebSocket.
  static const int sending = 0;

  /// Handed to the WebSocket (there is no delivery receipt).
  static const int sent = 1;

  /// The send failed; the message stays local with a failed marker.
  static const int failed = 2;
}

/// One attachment of an album message. Albums are stored as a JSON list on
/// [PrivateMessage.albumJson], so a new attachment type does not need a Hive
/// schema for every field.
class AlbumItem {
  AlbumItem({
    required this.mediaId,
    required this.type,
    required this.size,
    this.width,
    this.height,
    this.durationMs,
    this.fileName,
    this.localPath,
    this.status = MediaDownloadStatus.ready,
  });

  String mediaId;

  /// [MediaType.name] of this item.
  String type;
  int size;
  int? width;
  int? height;
  int? durationMs;
  String? fileName;

  /// Encrypted-at-rest file on this device, null until downloaded/sent.
  String? localPath;
  int status;

  MediaType? get mediaType {
    try {
      return MediaType.values.byName(type);
    } catch (_) {
      return null;
    }
  }

  bool get isReady =>
      status == MediaDownloadStatus.ready && localPath != null;

  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        'type': type,
        'size': size,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationMs != null) 'durationMs': durationMs,
        if (fileName != null) 'fileName': fileName,
        if (localPath != null) 'localPath': localPath,
        'status': status,
      };

  static AlbumItem fromJson(Map<String, dynamic> json) => AlbumItem(
        mediaId: json['mediaId'] as String,
        type: json['type'] as String,
        size: (json['size'] as num).toInt(),
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        durationMs: (json['durationMs'] as num?)?.toInt(),
        fileName: json['fileName'] as String?,
        localPath: json['localPath'] as String?,
        status: (json['status'] as num?)?.toInt() ?? MediaDownloadStatus.ready,
      );
}

@HiveType(typeId: 3)
class PrivateMessage extends HiveObject {
  @HiveField(0)
  String senderId;
  @HiveField(1)
  String message;
  @HiveField(2)
  DateTime sentAt;
  @HiveField(3)
  DateTime receivedAt;
  @HiveField(4)
  bool read;

  // Media attachment fields (all null for plain text messages).

  /// Server-side media id (used for download/confirm). May be null once the
  /// file has been confirmed/deleted on the server but kept locally.
  @HiveField(5)
  String? mediaId;

  /// [MediaType.name] of the attachment, or null for text messages and albums.
  @HiveField(6)
  String? mediaTypeStr;

  /// Absolute path to the encrypted-at-rest media file on the device.
  @HiveField(7)
  String? localPath;

  /// Size of the original (plaintext) media in bytes.
  @HiveField(8)
  int? mediaSize;

  /// Optional pixel width (images, gifs, videos).
  @HiveField(9)
  int? width;

  /// Optional pixel height (images, gifs, videos).
  @HiveField(10)
  int? height;

  /// Optional duration in milliseconds (videos, voice messages).
  @HiveField(11)
  int? durationMs;

  /// Download status, see [MediaDownloadStatus]. Defaults to ready (sent media).
  @HiveField(12, defaultValue: MediaDownloadStatus.ready)
  int downloadStatus;

  /// Original file name including the extension (documents etc.).
  @HiveField(13)
  String? fileName;

  /// Send state, see [SendStatus]. Old records default to sent.
  @HiveField(14, defaultValue: SendStatus.sent)
  int sendStatus;

  /// JSON list of [AlbumItem]s when this message carries more than one
  /// attachment. Null for text and single-media messages.
  @HiveField(15)
  String? albumJson;

  PrivateMessage(
    this.senderId,
    this.message,
    this.sentAt,
    this.receivedAt,
    this.read, {
    this.mediaId,
    this.mediaTypeStr,
    this.localPath,
    this.mediaSize,
    this.width,
    this.height,
    this.durationMs,
    this.downloadStatus = MediaDownloadStatus.ready,
    this.fileName,
    this.sendStatus = SendStatus.sent,
    this.albumJson,
  });

  bool get isMe => senderId == Singleton().profile.user.id;

  int get notificationId => receivedAt.microsecondsSinceEpoch % 0x7FFFFFFF;

  /// Whether this message carries a media attachment (single or album).
  bool get isMedia => mediaTypeStr != null || isAlbum;

  /// Whether this message is an album (more than one attachment).
  bool get isAlbum => albumJson != null;

  /// Decoded album items, empty for non-album messages.
  List<AlbumItem> get album {
    final raw = albumJson;
    if (raw == null) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => AlbumItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    } catch (_) {
      // Corrupted entry: behave like a message without attachments.
    }
    return const [];
  }

  /// Replaces the album items and serializes them back into [albumJson].
  void setAlbum(List<AlbumItem> items) {
    albumJson = jsonEncode(items.map((item) => item.toJson()).toList());
  }

  /// Local (encrypted-at-rest) files of this message, for deletion.
  List<String> get localPaths {
    final paths = <String>[];
    if (localPath != null) {
      paths.add(localPath!);
    }
    for (final item in album) {
      if (item.localPath != null) {
        paths.add(item.localPath!);
      }
    }
    return paths;
  }

  /// The decoded [MediaType] of the attachment, or null for text and albums.
  MediaType? get mediaType {
    if (albumJson != null || mediaTypeStr == null) {
      return null;
    }
    try {
      return MediaType.values.byName(mediaTypeStr!);
    } catch (_) {
      return null;
    }
  }

  /// Short text used in chat list previews and notifications. Falls back to a
  /// localized media label when a media message has no caption.
  String get preview {
    if (!isMedia || message.isNotEmpty) {
      return message;
    }
    if (isAlbum) {
      return '${'mediaAlbum'.tr()} (${album.length})';
    }
    switch (mediaType) {
      case MediaType.image:
        return 'mediaPhoto'.tr();
      case MediaType.gif:
        return 'mediaGif'.tr();
      case MediaType.video:
        return 'mediaVideo'.tr();
      case MediaType.voice:
        return 'mediaVoice'.tr();
      case MediaType.file:
        return fileName ?? 'mediaFile'.tr();
      case null:
        return message;
    }
  }
}
