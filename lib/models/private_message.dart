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

@HiveType(typeId: 3)
class PrivateMessage extends HiveObject {
  @HiveField(0)
  int senderId;
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

  /// [MediaType.name] of the attachment, or null for text messages.
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
  });

  bool get isMe => senderId == Singleton().profile.user.id;

  int get notificationId => receivedAt.microsecondsSinceEpoch % 0x7FFFFFFF;

  /// Whether this message carries a media attachment.
  bool get isMedia => mediaTypeStr != null;

  /// The decoded [MediaType] of the attachment, or null for text messages.
  MediaType? get mediaType {
    if (mediaTypeStr == null) {
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
    switch (mediaType) {
      case MediaType.image:
        return 'mediaPhoto'.tr();
      case MediaType.gif:
        return 'mediaGif'.tr();
      case MediaType.video:
        return 'mediaVideo'.tr();
      case MediaType.voice:
        return 'mediaVoice'.tr();
      case null:
        return message;
    }
  }
}
