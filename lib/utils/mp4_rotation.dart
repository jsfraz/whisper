import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Reads the display rotation a phone writes into an mp4 instead of rotating
/// the pixels: a portrait clip is often stored as a landscape frame plus a
/// rotation in the track header.
///
/// The player plugin reports the same value, but not every platform and file
/// combination does, and a bubble sized from the unrotated frame shows a
/// portrait video lying on its side.
class Mp4Rotation {
  Mp4Rotation._();

  /// Rotation of the first track in degrees (0, 90, 180 or 270). Zero when the
  /// file is not an mp4 or carries no rotation.
  static Future<int> ofFile(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final end = await handle.length();
      final tkhd = await _findTkhd(handle, 0, end);
      return tkhd ?? 0;
    } catch (_) {
      return 0;
    } finally {
      await handle?.close();
    }
  }

  /// Walks the box tree (moov > trak > tkhd) without reading the media data.
  static Future<int?> _findTkhd(
      RandomAccessFile handle, int start, int end) async {
    var offset = start;
    while (offset + 8 <= end) {
      await handle.setPosition(offset);
      final header = await handle.read(8);
      if (header.length < 8) {
        return null;
      }
      final data = ByteData.sublistView(header);
      var size = data.getUint32(0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      var headerSize = 8;
      if (size == 1) {
        final large = await handle.read(8);
        if (large.length < 8) {
          return null;
        }
        size = ByteData.sublistView(large).getUint64(0);
        headerSize = 16;
      } else if (size == 0) {
        size = end - offset;
      }
      if (size < headerSize || offset + size > end) {
        return null;
      }
      final bodyStart = offset + headerSize;
      final bodyEnd = offset + size;
      if (type == 'moov' || type == 'trak') {
        final found = await _findTkhd(handle, bodyStart, bodyEnd);
        if (found != null) {
          return found;
        }
      } else if (type == 'tkhd') {
        return _rotationFromTkhd(handle, bodyStart, bodyEnd);
      }
      offset = bodyEnd;
    }
    return null;
  }

  /// The rotation hides in the tkhd display matrix: `a` and `b` of
  /// `[a b u c d v x y w]` are the cosine and sine of the angle.
  static Future<int?> _rotationFromTkhd(
      RandomAccessFile handle, int start, int end) async {
    if (end - start < 48) {
      return null;
    }
    await handle.setPosition(start);
    final payload = await handle.read(end - start);
    if (payload.isEmpty) {
      return null;
    }
    final data = ByteData.sublistView(payload);
    final version = payload[0];
    // version + flags, then timestamps and ids: the matrix follows them.
    var matrix = version == 1 ? 4 + 24 + 8 + 8 : 4 + 16 + 4 + 8 + 8;
    if (matrix + 8 > payload.length) {
      return null;
    }
    final a = data.getInt32(matrix) / 65536.0;
    final b = data.getInt32(matrix + 4) / 65536.0;
    if (a == 0 && b == 0) {
      return 0;
    }
    // The matrix maps the picture into the track; the display turns the other
    // way, which is why the angle is negated (ffmpeg does the same).
    final degrees = (-math.atan2(b, a) * 180 / math.pi).round();
    return ((degrees % 360) + 360) % 360;
  }
}
