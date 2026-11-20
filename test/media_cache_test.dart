import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/media_utils.dart';
import 'package:whisper/utils/singleton.dart';

/// A chat list disposes the rows that leave the viewport, so a photo scrolling
/// back into view used to be decrypted again from disk: the spinner stayed up
/// for as long as the queue behind it.
void main() {
  final key = List<int>.generate(32, (i) => i + 1);
  final plain = Uint8List.fromList(List<int>.generate(2048, (i) => i % 251));
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('whisper_media_cache_test');
    Singleton().boxCollectionKey = key;
  });

  tearDownAll(() async {
    MediaUtils.clearDecryptCache();
    await dir.delete(recursive: true);
  });

  Future<String> stored(String name) async {
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(await MediaUtils.encryptWith(plain, key));
    return path;
  }

  test('a decrypted attachment is served from memory the second time',
      () async {
    final path = await stored('one');
    expect(await MediaUtils.decryptAtRest(path), plain);

    // The file is gone, so only the cache can answer this one.
    await File(path).delete();
    expect(await MediaUtils.decryptAtRest(path), plain);
  });

  test('clearing the cache sends the next read back to the file', () async {
    final path = await stored('two');
    await MediaUtils.decryptAtRest(path);

    MediaUtils.clearDecryptCache();
    await File(path).delete();

    await expectLater(
        MediaUtils.decryptAtRest(path), throwsA(isA<FileSystemException>()));
  });
}
