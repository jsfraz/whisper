import 'dart:convert';

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:crypto/crypto.dart';

class CryptoUtils {
  /// PBKDF2 password derivation (https://pub.dev/documentation/cryptography/latest/cryptography/Pbkdf2-class.html)
  static Future<List<int>> pbkdf2(String password) async {
    final pbkdf2 = cryptography.Pbkdf2(
      macAlgorithm: cryptography.Hmac.sha256(),
      iterations: 310000,
      bits: 256,
    );
    List<int> salt = md5.convert(utf8.encode(password)).bytes;
    final key =
        await pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
    return await key.extractBytes();
  }
}
