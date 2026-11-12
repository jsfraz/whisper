import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/media_utils.dart';

void main() {
  test('re-encrypted media only decrypts with the new key', () async {
    final plain = Uint8List.fromList(List.generate(256, (i) => i % 251));
    final oldKey = List<int>.filled(32, 1);
    final newKey = List<int>.filled(32, 2);

    final blob = await MediaUtils.encryptWith(plain, oldKey);
    final reencrypted = await MediaUtils.encryptWith(
        await MediaUtils.decryptWith(blob, oldKey), newKey);

    expect(await MediaUtils.decryptWith(reencrypted, newKey), plain);
    await expectLater(
        MediaUtils.decryptWith(reencrypted, oldKey), throwsA(anything));
  });
}
