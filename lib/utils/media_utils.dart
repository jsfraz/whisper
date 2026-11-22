import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show BuildContext, IconData, Icons, MediaQuery;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import 'singleton.dart';
import 'utils.dart';

/// Result of encrypting a file for transport: the uploadable [blob]
/// (`nonce || mac || ciphertext`) and the ephemeral symmetric [key] that goes
/// into the [MediaReference].
class TransportEncryption {
  final Uint8List blob;
  final Uint8List key;

  /// Nonce of [blob]; kept so a resumed upload reproduces the same ciphertext.
  final Uint8List nonce;

  const TransportEncryption(this.blob, this.key, this.nonce);
}

/// Metadata extracted from a media file before sending.
class MediaProbe {
  final int? width;
  final int? height;
  final int? durationMs;

  const MediaProbe({this.width, this.height, this.durationMs});
}

/// Arguments passed to the AES-GCM compute() workers.
class _GcmArgs {
  final Uint8List data;
  final Uint8List key;

  /// Pinned nonce, used to reproduce a blob that is already partly uploaded.
  final Uint8List? nonce;

  const _GcmArgs(this.data, this.key, [this.nonce]);
}

/// AES-GCM nonce length (bytes).
const int _nonceLength = 12;

/// AES-GCM MAC length (bytes).
const int _macLength = 16;

/// Encrypt [data] with AES-256-GCM and return `nonce || mac || ciphertext`.
/// Top-level so it can run in a background isolate via [compute].
Future<Uint8List> _gcmEncrypt(_GcmArgs args) async {
  final algorithm = cryptography.AesGcm.with256bits();
  final secretKey = cryptography.SecretKey(args.key);
  final box = await algorithm.encrypt(args.data,
      secretKey: secretKey, nonce: args.nonce);
  final nonce = box.nonce;
  final mac = box.mac.bytes;
  final out = Uint8List(nonce.length + mac.length + box.cipherText.length);
  out.setRange(0, nonce.length, nonce);
  out.setRange(nonce.length, nonce.length + mac.length, mac);
  out.setRange(nonce.length + mac.length, out.length, box.cipherText);
  return out;
}

/// Decrypt a `nonce || mac || ciphertext` blob produced by [_gcmEncrypt].
Future<Uint8List> _gcmDecrypt(_GcmArgs args) async {
  final blob = args.data;
  final nonce = blob.sublist(0, _nonceLength);
  final mac = blob.sublist(_nonceLength, _nonceLength + _macLength);
  final cipher = blob.sublist(_nonceLength + _macLength);
  final algorithm = cryptography.AesGcm.with256bits();
  final secretKey = cryptography.SecretKey(args.key);
  final box = cryptography.SecretBox(
    cipher,
    nonce: nonce,
    mac: cryptography.Mac(mac),
  );
  final clear = await algorithm.decrypt(box, secretKey: secretKey);
  return Uint8List.fromList(clear);
}

/// Central helper for media attachments: transport + at-rest encryption,
/// pickers, the voice recorder, and metadata/thumbnail extraction.
///
/// Two independent encryption layers are used (keys never leave the device
/// unencrypted):
///   * Transport: a random per-file AES-256-GCM key encrypts the bytes that are
///     uploaded to the server. The key travels (RSA+AES wrapped) inside the
///     message [MediaReference].
///   * At-rest: downloaded/sent plaintext is re-encrypted with the app master
///     key ([Singleton.boxCollectionKey]) and stored on disk.
class MediaUtils {
  MediaUtils._();

  static const Uuid _uuid = Uuid();
  static final ImagePicker _imagePicker = ImagePicker();

  /// Version marker used by a single-media message envelope.
  static const int envelopeVersion = 1;

  /// Version marker used by an album envelope (media is a list of references).
  static const int envelopeVersionAlbum = 2;

  // ---------------------------------------------------------------------------
  // Transport encryption
  // ---------------------------------------------------------------------------

  /// Encrypt [bytes] for upload.
  ///
  /// A fresh key and nonce per file, unless [key] and [nonce] are given: a
  /// resumed upload must append the bytes the server already holds, so it
  /// re-encrypts with the same pair.
  static Future<TransportEncryption> encryptForTransport(Uint8List bytes,
      {Uint8List? key, Uint8List? nonce}) async {
    var keyBytes = key;
    if (keyBytes == null) {
      final algorithm = cryptography.AesGcm.with256bits();
      keyBytes = Uint8List.fromList(
          await (await algorithm.newSecretKey()).extractBytes());
    }
    final blob = await compute(_gcmEncrypt, _GcmArgs(bytes, keyBytes, nonce));
    return TransportEncryption(
        blob, keyBytes, Uint8List.fromList(blob.sublist(0, _nonceLength)));
  }

  /// Decrypt a downloaded [blob] using the transport [key] from the reference.
  static Future<Uint8List> decryptTransport(Uint8List blob, Uint8List key) {
    return compute(_gcmDecrypt, _GcmArgs(blob, key));
  }

  // ---------------------------------------------------------------------------
  // At-rest encryption (local persistence)
  // ---------------------------------------------------------------------------

  /// Encrypt plaintext [bytes] with the app master key and write them to the
  /// media directory. Returns the absolute path of the stored encrypted file.
  static Future<String> encryptAtRest(Uint8List bytes) async {
    final key = Uint8List.fromList(Singleton().boxCollectionKey);
    final blob = await compute(_gcmEncrypt, _GcmArgs(bytes, key));
    final dir = await mediaDir();
    final path = '$dir/${_uuid.v4()}';
    await File(path).writeAsBytes(blob, flush: true);
    return path;
  }

  /// Decrypt an at-rest file written by [encryptAtRest].
  ///
  /// Throttled: decrypting spawns an isolate per call, so a chat full of
  /// attachments would otherwise spawn one burst per scroll. Decrypted bytes
  /// are kept for the most recently shown attachments: a list disposes its
  /// rows when they leave the viewport, and decrypting the same photo again
  /// every time it scrolls back is what kept the spinner up.
  static Future<Uint8List> decryptAtRest(String path) async {
    final cached = _mediaCache.remove(path);
    if (cached != null) {
      _mediaCache[path] = cached;
      return cached;
    }
    return _withDecryptSlot(() async {
      final blob = await File(path).readAsBytes();
      final key = Uint8List.fromList(Singleton().boxCollectionKey);
      final plain = await compute(_gcmDecrypt, _GcmArgs(blob, key));
      _cacheBytes(path, plain);
      return plain;
    });
  }

  /// Decoded media kept in memory, oldest first.
  static final Map<String, Uint8List> _mediaCache = <String, Uint8List>{};
  static const int _maxCachedMedia = 24;
  static const int _maxCachedBytes = 64 << 20;
  static int _cachedBytes = 0;

  static void _cacheBytes(String path, Uint8List bytes) {
    final previous = _mediaCache.remove(path);
    if (previous != null) {
      _cachedBytes -= previous.length;
    }
    if (bytes.length > _maxCachedBytes) {
      return;
    }
    _mediaCache[path] = bytes;
    _cachedBytes += bytes.length;
    while (_mediaCache.length > _maxCachedMedia ||
        _cachedBytes > _maxCachedBytes) {
      _cachedBytes -= _mediaCache.remove(_mediaCache.keys.first)!.length;
    }
  }

  /// Drops the plaintext attachments held in memory, e.g. when the local media
  /// files are deleted.
  static void clearDecryptCache() {
    _mediaCache.clear();
    _cachedBytes = 0;
  }

  /// Decode width for [Image.memory]: a camera photo must not be decoded at its
  /// full resolution for a thumbnail-sized box.
  static int decodeWidth(BuildContext context, double logicalWidth) =>
      (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round();

  static const int _maxConcurrentDecrypts = 2;
  static int _activeDecrypts = 0;
  static final List<Completer<void>> _decryptWaiters = [];

  /// Runs [task] while at most [_maxConcurrentDecrypts] decrypts are alive.
  static Future<T> _withDecryptSlot<T>(Future<T> Function() task) async {
    while (_activeDecrypts >= _maxConcurrentDecrypts) {
      final waiter = Completer<void>();
      _decryptWaiters.add(waiter);
      await waiter.future;
    }
    _activeDecrypts++;
    try {
      return await task();
    } finally {
      _activeDecrypts--;
      if (_decryptWaiters.isNotEmpty) {
        _decryptWaiters.removeAt(0).complete();
      }
    }
  }

  /// Encrypt bytes with an explicit AES-GCM key (no singleton lookup).
  static Future<Uint8List> encryptWith(Uint8List bytes, List<int> key) {
    return compute(_gcmEncrypt, _GcmArgs(bytes, Uint8List.fromList(key)));
  }

  /// Decrypt a blob with an explicit AES-GCM key (no singleton lookup).
  static Future<Uint8List> decryptWith(Uint8List blob, List<int> key) {
    return compute(_gcmDecrypt, _GcmArgs(blob, Uint8List.fromList(key)));
  }

  /// Phase 1 of a password change: decrypts every at-rest media file with
  /// [oldKey] and writes `<file>.new` encrypted with [newKey]. Originals stay
  /// untouched until [commitRekey], so an interrupted change loses nothing.
  static Future<List<String>> stageRekey(
      List<int> oldKey, List<int> newKey) async {
    final dir = Directory(await mediaDir());
    final staged = <String>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is! File || entity.path.endsWith('.new')) {
          continue;
        }
        final blob = await entity.readAsBytes();
        final Uint8List plain;
        try {
          plain = await decryptWith(blob, oldKey);
        } catch (e) {
          // A file that does not decrypt with the current key is already
          // unreadable; leave it alone instead of failing the whole change.
          debugPrint('rekey skipped ${entity.path}: $e');
          continue;
        }
        final encrypted = await encryptWith(plain, newKey);
        final target = '${entity.path}.new';
        await File(target).writeAsBytes(encrypted, flush: true);
        staged.add(target);
      }
    } catch (e) {
      await discardRekey(staged);
      rethrow;
    }
    return staged;
  }

  /// Phase 2: replaces the originals with the staged files.
  static Future<void> commitRekey(List<String> staged) async {
    for (final path in staged) {
      await File(path).rename(path.substring(0, path.length - '.new'.length));
    }
  }

  /// Drops staged files after a failed key change.
  static Future<void> discardRekey(List<String> staged) async {
    for (final path in staged) {
      try {
        await File(path).delete();
      } catch (_) {
        // Staged files are disposable.
      }
    }
  }

  /// Decrypt an at-rest file into a temporary plaintext file (for the platform
  /// video/audio players). The caller is responsible for deleting it on dispose.
  static Future<File> materializeTempFile(String path, String extension) async {
    final bytes = await decryptAtRest(path);
    final tmpDir = await getTemporaryDirectory();
    final file = File('${tmpDir.path}/whisper_media_${_uuid.v4()}$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ---------------------------------------------------------------------------
  // Filesystem helpers
  // ---------------------------------------------------------------------------

  /// Directory where encrypted-at-rest media files live.
  static Future<String> mediaDir() async {
    final dir = '${await Utils.getCacheDir()}/media';
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// Writes plaintext bytes to a temporary file, e.g. for keyboard-inserted
  /// GIFs that then go through the media pipeline. Never into [mediaDir],
  /// which must only hold encrypted files.
  static Future<File> writeTempBytes(Uint8List bytes, String extension) async {
    final tmpDir = await getTemporaryDirectory();
    final file = File('${tmpDir.path}/whisper_send_${_uuid.v4()}.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Whether a file name belongs to the app's plaintext temp files.
  static bool isTempMediaName(String name) =>
      name.startsWith('whisper_media_') || name.startsWith('whisper_send_');

  /// Remove plaintext media left in the temp directory.
  ///
  /// Playback materializes decrypted files and the keyboard writes plaintext
  /// GIFs; both are deleted on dispose, but a crash leaves them behind. At
  /// rest they must not exist.
  static Future<void> clearTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final entity in dir.list()) {
        if (entity is! File) {
          continue;
        }
        if (isTempMediaName(baseName(entity.path))) {
          await entity.delete();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to clear temp media: $e');
      }
    }
  }

  /// Delete a single (encrypted) media file, ignoring errors.
  static Future<void> deleteLocalFile(String? path) async {
    if (path == null) {
      return;
    }
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to delete media file $path: $e');
      }
    }
  }

  /// Remove every locally stored media file (used on full cache wipe).
  static Future<void> clearMediaDir() async {
    clearDecryptCache();
    try {
      final dir = Directory('${await Utils.getCacheDir()}/media');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to clear media dir: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Type detection & extensions
  // ---------------------------------------------------------------------------

  /// Detect the [MediaType] of a file from its mime type / extension.
  static MediaType detectType(String path, {String? mimeType}) {
    final mime = mimeType ?? lookupMimeType(path) ?? '';
    final lower = path.toLowerCase();
    if (mime == 'image/gif' || lower.endsWith('.gif')) {
      return MediaType.gif;
    }
    if (mime.startsWith('image/')) {
      return MediaType.image;
    }
    if (mime.startsWith('video/')) {
      return MediaType.video;
    }
    if (mime.startsWith('audio/')) {
      return MediaType.voice;
    }
    // Anything else is sent as a plain file.
    return MediaType.file;
  }

  /// Default file extension used when materializing a temp file for playback,
  /// or as a last resort when a real name is not known.
  static String extensionForType(MediaType type) {
    switch (type) {
      case MediaType.image:
        return '.jpg';
      case MediaType.gif:
        return '.gif';
      case MediaType.video:
        return '.mp4';
      case MediaType.voice:
        return '.m4a';
      case MediaType.file:
        return '';
    }
  }

  /// Largest upload the server accepts (mirrors MEDIA_MAX_UPLOAD_SIZE).
  ///
  /// shortcut: a file is still encrypted, chunked and decrypted in memory, so
  /// raising this much further needs streaming GCM before it is safe.
  static const int maxUploadBytes = 100 * 1024 * 1024;

  /// Upload chunk size (mirrors what the server appends per request).
  static const int uploadChunkBytes = 1024 * 1024;

  /// AES-GCM overhead added to every uploaded file (nonce + mac).
  static const int transportOverheadBytes = _nonceLength + _macLength;

  /// Whether a plaintext file of [plaintextBytes] fits the server limit once
  /// it is encrypted for transport.
  static bool uploadFits(int plaintextBytes) =>
      plaintextBytes + transportOverheadBytes <= maxUploadBytes;

  /// Last path segment of [path], i.e. the file name with its extension.
  static String baseName(String path) => path.split(RegExp(r'[\\/]')).last;

  /// Icon for a document, picked from its extension. Everything unknown falls
  /// back to a plain file.
  static IconData iconForFileName(String? fileName) {
    final dot = fileName?.lastIndexOf('.') ?? -1;
    final extension = dot >= 0 && dot < (fileName!.length - 1)
        ? fileName.substring(dot + 1).toLowerCase()
        : '';
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'ods':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
      case 'odp':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'html':
        return Icons.code;
      case 'txt':
      case 'md':
      case 'log':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Human readable size, e.g. `1.4 MB`.
  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    const units = ['KB', 'MB', 'GB'];
    double value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  /// Translation key for a short human label of a media type (used in previews
  /// and notifications).
  static String labelKeyForType(MediaType type) {
    switch (type) {
      case MediaType.image:
        return 'mediaPhoto';
      case MediaType.gif:
        return 'mediaGif';
      case MediaType.video:
        return 'mediaVideo';
      case MediaType.voice:
        return 'mediaVoice';
      case MediaType.file:
        return 'mediaFile';
    }
  }

  // ---------------------------------------------------------------------------
  // Metadata & thumbnails
  // ---------------------------------------------------------------------------

  /// Decode the pixel dimensions of an encoded image (png/jpg/gif/webp).
  static Future<MediaProbe> imageDimensions(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final probe = MediaProbe(width: image.width, height: image.height);
      image.dispose();
      codec.dispose();
      return probe;
    } catch (_) {
      return const MediaProbe();
    }
  }

  /// Read width/height/duration of a video by briefly initializing a controller.
  static Future<MediaProbe> videoMetadata(String filePath) async {
    final controller = VideoPlayerController.file(File(filePath));
    try {
      await controller.initialize();
      final size = controller.value.size;
      final duration = controller.value.duration;
      return MediaProbe(
        width: size.width.round(),
        height: size.height.round(),
        durationMs: duration.inMilliseconds,
      );
    } catch (_) {
      return const MediaProbe();
    } finally {
      await controller.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Message envelope codec
  // ---------------------------------------------------------------------------

  /// Build the plaintext (pre-encryption) bytes for a media message: a JSON
  /// envelope wrapping the [reference] and optional [caption]. [viewOnce] marks
  /// a single-view attachment; the flag rides inside the ciphertext, so only
  /// the two participants know.
  static Uint8List buildMediaEnvelope(MediaReference reference, String caption,
      {bool forwarded = false, bool viewOnce = false}) {
    final map = <String, dynamic>{
      'whisperMsg': envelopeVersion,
      'kind': 'media',
      'caption': caption,
      'media': reference.toJson(),
      if (forwarded) 'forwarded': true,
      if (viewOnce) 'viewOnce': true,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  /// Build the plaintext (pre-encryption) bytes for an album message: a JSON
  /// envelope wrapping [references] and an optional [caption].
  static Uint8List buildAlbumEnvelope(
      List<MediaReference> references, String caption,
      {bool forwarded = false, bool viewOnce = false}) {
    final map = <String, dynamic>{
      'whisperMsg': envelopeVersionAlbum,
      'kind': 'media',
      'caption': caption,
      'media': references.map((reference) => reference.toJson()).toList(),
      if (forwarded) 'forwarded': true,
      if (viewOnce) 'viewOnce': true,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  /// Try to parse decrypted [plaintext] as a media envelope (single or album).
  /// Returns null when the bytes are not a media envelope (i.e. plain text).
  static ParsedMediaEnvelope? tryParseMediaEnvelope(Uint8List plaintext) {
    try {
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is Map && decoded['kind'] == 'media') {
        final caption = (decoded['caption'] as String?) ?? '';
        final forwarded = decoded['forwarded'] == true;
        final viewOnce = decoded['viewOnce'] == true;
        if (decoded['whisperMsg'] == envelopeVersion &&
            decoded['media'] is Map) {
          final reference = MediaReference.fromJson(
              Map<String, dynamic>.from(decoded['media'] as Map));
          return ParsedMediaEnvelope([reference], caption,
              forwarded: forwarded, viewOnce: viewOnce);
        }
        if (decoded['whisperMsg'] == envelopeVersionAlbum &&
            decoded['media'] is List) {
          final references = (decoded['media'] as List)
              .whereType<Map>()
              .map((item) =>
                  MediaReference.fromJson(Map<String, dynamic>.from(item)))
              .toList();
          if (references.isNotEmpty) {
            return ParsedMediaEnvelope(references, caption,
                forwarded: forwarded, viewOnce: viewOnce);
          }
        }
      }
    } catch (_) {
      // Not JSON / not a media envelope -> treat as plain text.
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Pickers
  // ---------------------------------------------------------------------------

  /// Capture a photo with the camera.
  static Future<File?> pickImageFromCamera() async {
    final picked = await _imagePicker.pickImage(
        source: ImageSource.camera, imageQuality: 85);
    return picked == null ? null : File(picked.path);
  }

  /// Capture a video with the camera.
  static Future<File?> pickVideoFromCamera() async {
    final picked = await _imagePicker.pickVideo(
        source: ImageSource.camera, maxDuration: const Duration(minutes: 1));
    return picked == null ? null : File(picked.path);
  }

  /// Pick an arbitrary file (images, videos, documents, ...).
  static Future<File?> pickFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    return path == null ? null : File(path);
  }

  /// Pick several images/videos from the gallery at once (album).
  static Future<List<File>> pickMultipleMediaFromGallery() async {
    final picked = await _imagePicker.pickMultipleMedia();
    return picked.map((x) => File(x.path)).toList();
  }

  /// Pick several arbitrary files at once (album).
  static Future<List<File>> pickMultipleFiles() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    return picked
        .map((file) => file.path)
        .whereType<String>()
        .map((path) => File(path))
        .toList();
  }

  /// Whether [file] is a photo, gif or video (the "File" attachment must not
  /// send those; the gallery and camera entries are for them).
  static bool isVisualMedia(File file) {
    final type = detectType(file.path);
    return type == MediaType.image ||
        type == MediaType.gif ||
        type == MediaType.video;
  }
}

/// Parsed media envelope: one or more [MediaReference]s plus the caption.
class ParsedMediaEnvelope {
  final List<MediaReference> references;
  final String caption;

  /// The sender passed on somebody else's attachment instead of writing it.
  final bool forwarded;

  /// A single-view attachment: one open, then gone for both sides.
  final bool viewOnce;

  const ParsedMediaEnvelope(this.references, this.caption,
      {this.forwarded = false, this.viewOnce = false});
}

/// Thin wrapper around the [AudioRecorder] for hold-to-record voice messages.
class MediaRecorderController {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  DateTime? _startedAt;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Start recording to a temporary .m4a file.
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/whisper_voice_${const Uuid().v4()}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: _path!,
    );
    _startedAt = DateTime.now();
  }

  /// Stop recording and return the resulting file and its duration.
  Future<RecordedVoice?> stop() async {
    final path = await _recorder.stop();
    final durationMs = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inMilliseconds;
    if (path == null) {
      return null;
    }
    return RecordedVoice(File(path), durationMs);
  }

  /// Abort recording and discard the partial file.
  Future<void> cancel() async {
    try {
      await _recorder.stop();
    } catch (_) {
      // ignore
    }
    await MediaUtils.deleteLocalFile(_path);
  }

  /// Live amplitude stream for the recording UI.
  Stream<Amplitude> amplitudeStream() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 200));

  Future<void> dispose() => _recorder.dispose();
}

/// A finished voice recording.
class RecordedVoice {
  final File file;
  final int durationMs;

  const RecordedVoice(this.file, this.durationMs);
}
