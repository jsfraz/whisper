import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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

  const TransportEncryption(this.blob, this.key);
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

  const _GcmArgs(this.data, this.key);
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
  final box = await algorithm.encrypt(args.data, secretKey: secretKey);
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

  /// Version marker used by the media message envelope.
  static const int envelopeVersion = 1;

  // ---------------------------------------------------------------------------
  // Transport encryption
  // ---------------------------------------------------------------------------

  /// Encrypt [bytes] with a fresh random key for upload.
  static Future<TransportEncryption> encryptForTransport(Uint8List bytes) async {
    final algorithm = cryptography.AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKey();
    final keyBytes = Uint8List.fromList(await secretKey.extractBytes());
    final blob = await compute(_gcmEncrypt, _GcmArgs(bytes, keyBytes));
    return TransportEncryption(blob, keyBytes);
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
  static Future<Uint8List> decryptAtRest(String path) async {
    final blob = await File(path).readAsBytes();
    final key = Uint8List.fromList(Singleton().boxCollectionKey);
    return compute(_gcmDecrypt, _GcmArgs(blob, key));
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
    if (mime.startsWith('video/')) {
      return MediaType.video;
    }
    if (mime.startsWith('audio/')) {
      return MediaType.voice;
    }
    return MediaType.image;
  }

  /// Default file extension used when materializing a temp file for playback.
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
    }
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
  /// envelope wrapping the [reference] and optional [caption].
  static Uint8List buildMediaEnvelope(MediaReference reference, String caption) {
    final map = <String, dynamic>{
      'whisperMsg': envelopeVersion,
      'kind': 'media',
      'caption': caption,
      'media': reference.toJson(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  /// Try to parse decrypted [plaintext] as a media envelope. Returns null when
  /// the bytes are not a media envelope (i.e. a plain text message).
  static ParsedMediaEnvelope? tryParseMediaEnvelope(Uint8List plaintext) {
    try {
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is Map &&
          decoded['whisperMsg'] == envelopeVersion &&
          decoded['kind'] == 'media' &&
          decoded['media'] is Map) {
        final reference = MediaReference.fromJson(
            Map<String, dynamic>.from(decoded['media'] as Map));
        final caption = (decoded['caption'] as String?) ?? '';
        return ParsedMediaEnvelope(reference, caption);
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
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 1));
    return picked == null ? null : File(picked.path);
  }

  /// Pick a single image or video from the gallery.
  static Future<File?> pickMediaFromGallery() async {
    final picked = await _imagePicker.pickMedia();
    return picked == null ? null : File(picked.path);
  }

  /// Pick a GIF file.
  static Future<File?> pickGif() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gif'],
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  /// Pick an arbitrary media (image/video) file.
  static Future<File?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.media);
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }
}

/// Parsed media envelope: a [MediaReference] plus its caption.
class ParsedMediaEnvelope {
  final MediaReference reference;
  final String caption;

  const ParsedMediaEnvelope(this.reference, this.caption);
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
    final durationMs =
        _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMilliseconds;
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
