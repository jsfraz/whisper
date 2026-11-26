import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:hive/hive.dart';
import 'package:shept_websocket_client_dart/models/media_reference.dart';
import 'package:shept_websocket_client_dart/models/media_type.dart';

import '../utils/singleton.dart';
import '../utils/text_envelope.dart';

part 'private_message.g.dart';

/// Download status of a media attachment stored locally.
class MediaDownloadStatus {
  /// Not yet downloaded/decrypted (recipient side, in progress).
  static const int pending = 0;

  /// Downloaded, decrypted and stored encrypted-at-rest locally.
  static const int ready = 1;

  /// Download or decryption failed; can be retried.
  static const int failed = 2;

  /// The server no longer has the file: it was confirmed on another device,
  /// expired, or the sender's account was cleaned up. Retrying cannot help.
  static const int expired = 3;
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
    this.keyB64,
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

  /// Base64 of the transport key of the attachment, kept so a caption can be
  /// re-encrypted into a new envelope later. Null on rows stored before it was
  /// kept.
  String? keyB64;

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

  bool get isReady => status == MediaDownloadStatus.ready && localPath != null;

  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        'type': type,
        'size': size,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationMs != null) 'durationMs': durationMs,
        if (fileName != null) 'fileName': fileName,
        if (keyB64 != null) 'keyB64': keyB64,
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
        keyB64: json['keyB64'] as String?,
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

  /// Sender of the message this one quotes, null when it is not a reply.
  @HiveField(16)
  String? replyToSenderId;

  /// Client timestamp of the quoted message, null when it is not a reply.
  @HiveField(17)
  DateTime? replyToSentAt;

  /// Preview of the quoted message, kept here so the quote survives its
  /// original being deleted on this device.
  @HiveField(18)
  String? replyToPreview;

  /// Archive id from the server, null for a message this device only ever sent
  /// and for rows stored before the id was kept. Deleting on the server needs
  /// it.
  @HiveField(19)
  String? id;

  /// Instant the sender last edited the text, null when it was never edited.
  @HiveField(20)
  DateTime? editedAt;

  /// Emoji reaction of each participant, keyed by user id. Null when nobody
  /// reacted.
  @HiveField(21)
  Map<String, String>? reactions;

  /// Whether the message was forwarded: the sender passed on somebody else's
  /// text instead of writing it.
  @HiveField(22, defaultValue: false)
  bool forwarded;

  /// JSON of the media reference (id, key, type, size, metadata) for a single
  /// attachment. Kept so editing the caption can build a new envelope without
  /// the original upload; null on rows stored before it was kept.
  @HiveField(23)
  String? mediaRefJson;

  /// When the message must be gone from this device: the disappearing-message
  /// deadline, or the view-once life. Null means the retention applies.
  @HiveField(24)
  DateTime? expiresAt;

  /// Set on a control message that carries no text: "propose", "accept" or
  /// "decline" of a chat setting. Null on ordinary messages.
  @HiveField(25)
  String? systemState;

  /// Seconds carried by a control message.
  @HiveField(26, defaultValue: 0)
  int systemSeconds;

  /// A single-view attachment: opened once, then gone for both sides.
  @HiveField(27, defaultValue: false)
  bool viewOnce;

  /// JSON of a static location ({lat, lng, accuracy?, label?}) sent as a
  /// message; null for everything else.
  @HiveField(28)
  String? locationJson;

  /// When the receiver opened this view-once attachment; null while it is still
  /// unopened. Server-reported, so both sides see the same instant.
  @HiveField(29)
  DateTime? openedAt;

  /// When the sender deleted this message for everyone. The row stays as a
  /// tombstone in the conversation, with no content left.
  @HiveField(30)
  DateTime? deletedAt;

  /// Cache for [album], keyed by the [albumJson] it was decoded from.
  String? _albumCacheJson;
  List<AlbumItem>? _albumCache;

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
    this.replyToSenderId,
    this.replyToSentAt,
    this.replyToPreview,
    this.editedAt,
    this.reactions,
    this.forwarded = false,
    this.mediaRefJson,
    this.expiresAt,
    this.systemState,
    this.systemSeconds = 0,
    this.viewOnce = false,
    this.locationJson,
    this.openedAt,
    this.deletedAt,
  });

  /// The static location carried by this message, null for everything else.
  LocationRef? get location {
    final raw = locationJson;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return LocationRef.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// A control message: it carries a chat setting, not text to read.
  bool get isSystem => systemState != null;

  /// True once the disappearing deadline of this message has passed.
  bool get isExpired {
    final deadline = expiresAt;
    return deadline != null && deadline.isBefore(DateTime.now());
  }

  /// References needed to re-encrypt this message with a new caption, null for
  /// text messages and when their key was never kept.
  List<MediaReference>? get mediaReferences {
    if (isAlbum) {
      final refs = <MediaReference>[];
      for (final item in album) {
        final key = item.keyB64 == null ? null : base64Decode(item.keyB64!);
        final type = item.mediaType;
        if (key == null || type == null) {
          return null;
        }
        refs.add(MediaReference(item.mediaId, key, type, item.size,
            width: item.width,
            height: item.height,
            durationMs: item.durationMs,
            fileName: item.fileName));
      }
      return refs.isEmpty ? null : refs;
    }
    final raw = mediaRefJson;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return [
        MediaReference.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map))
      ];
    } catch (_) {
      return null;
    }
  }

  /// Whether this video was recorded as a round note.
  ///
  /// The flag rides in the media reference, which only exists once the upload
  /// finished; while a note is still sending, the message carries a bare marker
  /// written when the send started.
  bool get isVideoNote {
    final references = mediaReferences;
    if (references != null && references.isNotEmpty) {
      return references.first.videoNote;
    }
    final raw = mediaRefJson;
    if (raw == null || raw.isEmpty) {
      return false;
    }
    try {
      final json = jsonDecode(raw);
      return json is Map && json['videoNote'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Whether the sender edited the text after sending it.
  bool get isEdited => editedAt != null;

  /// Distinct reaction emoji, sorted so the chips do not jump around.
  List<String> get reactionEmojis =>
      (reactions?.values.toSet().toList() ?? [])..sort();

  /// The quoted message, or null when this message is not a reply.
  ReplyRef? get replyTo {
    final senderId = replyToSenderId;
    final sentAt = replyToSentAt;
    if (senderId == null || sentAt == null) {
      return null;
    }
    return ReplyRef(
      senderId: senderId,
      sentAt: sentAt,
      preview: replyToPreview ?? '',
    );
  }

  /// Stores (or clears) the message this one quotes.
  void setReplyTo(ReplyRef? reply) {
    replyToSenderId = reply?.senderId;
    replyToSentAt = reply?.sentAt;
    replyToPreview = reply?.preview;
  }

  /// Whether this message quotes another one.
  bool get isReply => replyToSentAt != null;

  /// Stored instead of the text when a message cannot be decrypted. It keeps a
  /// visible gap in the chat, and the receiver only acks what it stored, so the
  /// server still has the ciphertext.
  static const String undecryptableMarker = '\uE000shept-undecryptable';

  bool get isMe => senderId == Singleton().profile.user.id;

  /// Whether the stored text is the placeholder of an undecryptable message.
  bool get isUndecryptable => message == undecryptableMarker;

  /// Whether the sender deleted this message for everyone: the row stays as a
  /// tombstone and carries nothing.
  bool get isDeleted => deletedAt != null;

  int get notificationId => receivedAt.microsecondsSinceEpoch % 0x7FFFFFFF;

  /// Whether this message carries a media attachment (single or album).
  bool get isMedia => mediaTypeStr != null || isAlbum;

  /// Whether this message is an album (more than one attachment).
  bool get isAlbum => albumJson != null;

  /// Decoded album items, empty for non-album messages.
  ///
  /// Cached per [albumJson]: the getter is hit from previews, deletion paths
  /// and album widgets, and decoding the JSON on every access is wasteful.
  List<AlbumItem> get album {
    final raw = albumJson;
    if (raw == null) {
      return const [];
    }
    if (raw == _albumCacheJson) {
      return _albumCache ?? const [];
    }
    final decodedItems = _decodeAlbum(raw);
    _albumCacheJson = raw;
    _albumCache = decodedItems;
    return decodedItems;
  }

  List<AlbumItem> _decodeAlbum(String raw) {
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
    _albumCacheJson = null;
    _albumCache = null;
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
    if (isDeleted) {
      return 'messageDeleted'.tr();
    }
    if (isUndecryptable) {
      return 'messageUndecryptable'.tr();
    }
    if (isSystem) {
      return 'disappearingChanged'.tr();
    }
    // A view-once message never shows its content in a list: not its caption,
    // not the coordinates of a location, before or after it is opened.
    if (viewOnce) {
      return openedAt == null ? 'viewOnceMedia'.tr() : 'viewOnceOpened'.tr();
    }
    final location = this.location;
    if (location != null) {
      // Without the pin: a map marker belongs in the bubble, not in a one-line
      // summary, and rows stored by an older build keep their emoji in the text.
      return '${location.lat.toStringAsFixed(5)}, '
          '${location.lng.toStringAsFixed(5)}';
    }
    return _previewText;
  }

  /// The untrimmed preview: the text, or a media label when there is none.
  String get _previewText {
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
      case MediaType.sticker:
        return 'mediaSticker'.tr();
      case null:
        return message;
    }
  }
}
