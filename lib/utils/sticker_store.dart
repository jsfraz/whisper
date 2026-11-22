import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'cache_utils.dart';
import 'media_utils.dart';

/// One sticker of the local collection.
class Sticker {
  const Sticker(this.id, this.path);

  /// Id of the entry in the sticker box.
  final String id;

  /// Encrypted-at-rest file on this device.
  final String path;
}

/// Custom stickers: pictures imported from a file, kept on this device.
///
/// There is no third-party sticker store: the bytes are the user's, encrypted
/// at rest like every other attachment, and the only metadata is the path.
class StickerStore {
  StickerStore._();

  static const Uuid _uuid = Uuid();

  /// Extensions a sticker may have. The renderer plays animated GIFs natively,
  /// so both still and animated stickers work without extra code.
  static const List<String> _extensions = ['.png', '.gif', '.webp', '.jpg'];

  static bool _supported(String? fileName) {
    if (fileName == null) {
      return false;
    }
    final lower = fileName.toLowerCase();
    return _extensions.any(lower.endsWith);
  }

  /// Every sticker still present on disk, oldest first.
  static Future<List<Sticker>> all() async {
    final entries = await CacheUtils.getStickers();
    final stickers = <Sticker>[];
    for (final entry in entries.entries) {
      if (File(entry.value).existsSync()) {
        stickers.add(Sticker(entry.key, entry.value));
      }
    }
    return stickers;
  }

  /// Imports [bytes] as a new sticker. Null when the file is not a picture.
  static Future<Sticker?> add(Uint8List bytes, String? fileName) async {
    if (!_supported(fileName)) {
      return null;
    }
    final path = await MediaUtils.encryptAtRest(bytes);
    final sticker = Sticker(_uuid.v4(), path);
    await CacheUtils.putSticker(sticker.id, sticker.path);
    return sticker;
  }

  /// Removes a sticker and its file.
  static Future<void> remove(Sticker sticker) async {
    await CacheUtils.deleteSticker(sticker.id);
    await MediaUtils.deleteLocalFile(sticker.path);
  }
}
