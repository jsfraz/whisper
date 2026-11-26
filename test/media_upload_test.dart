import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shept/utils/media_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A resumed upload appends to the bytes the server already holds, so it must
  // rebuild the exact same ciphertext from the recorded key and nonce.
  test('re-encrypting with the recorded key and nonce reproduces the blob',
      () async {
    final bytes = Uint8List.fromList(List.generate(5000, (i) => i % 251));

    final first = await MediaUtils.encryptForTransport(bytes);
    final resumed = await MediaUtils.encryptForTransport(bytes,
        key: first.key, nonce: first.nonce);

    expect(resumed.blob, equals(first.blob));
    expect(resumed.nonce, equals(first.nonce));
    expect(await MediaUtils.decryptTransport(resumed.blob, resumed.key),
        equals(bytes));
  });

  test('a fresh upload encrypts with its own key', () async {
    final bytes = Uint8List.fromList(List.generate(5000, (i) => i % 251));

    final first = await MediaUtils.encryptForTransport(bytes);
    final second = await MediaUtils.encryptForTransport(bytes);

    expect(second.key, isNot(equals(first.key)));
    expect(second.blob, isNot(equals(first.blob)));
  });
}
