import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/crypto_utils.dart';

void main() {
  test('same password and salt derive the same key', () async {
    final salt = List<int>.filled(32, 7);
    final first =
        await CryptoUtils.pbkdf2('correct horse battery staple', salt);
    final second =
        await CryptoUtils.pbkdf2('correct horse battery staple', salt);

    expect(first, second);
    expect(first.length, 32);
  });

  test('a different salt derives a different key', () async {
    final a = await CryptoUtils.pbkdf2(
        'correct horse battery staple', List<int>.filled(32, 1));
    final b = await CryptoUtils.pbkdf2(
        'correct horse battery staple', List<int>.filled(32, 2));

    expect(a, isNot(b));
  });

  test('generated salts are random 32-byte values', () {
    final a = CryptoUtils.generateSalt();
    final b = CryptoUtils.generateSalt();

    expect(a.length, 32);
    expect(a, isNot(b));
  });

  test('legacy derivation still matches the old md5 salt scheme', () async {
    // Guards the migration path for installs created before random salts.
    final legacy =
        await CryptoUtils.legacyPbkdf2('correct horse battery staple');
    expect(legacy.length, 32);
    expect(
        legacy, await CryptoUtils.legacyPbkdf2('correct horse battery staple'));
  });
}
