import 'dart:convert';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' as djwt;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:crypto/crypto.dart';

class CryptoUtils {
  /// Generate RSA keypair synchronously
  static AsymmetricKeyPair<PublicKey, PrivateKey> _getRSAKeyPair(
      SecureRandom secureRandom) {
    var rsaParams = RSAKeyGeneratorParameters(BigInt.from(65537), 4096, 12);
    var params = ParametersWithRandom(rsaParams, secureRandom);

    var keyGenerator = RSAKeyGenerator();
    keyGenerator.init(params);

    return keyGenerator.generateKeyPair();
  }

  /// Generate RSA keypair asynchronously
  static Future<AsymmetricKeyPair<PublicKey, PrivateKey>>
      getRSAKeyPair() async {
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(Uint8List.fromList(
        List.generate(32, (i) => i)))); // Seed with random bytes

    return await compute(_getRSAKeyPair, secureRandom);
  }

  ///
  static String _jwtSignRsa(Map<String, dynamic> data) {
    final jwt = djwt.JWT({
      'iss': data['iss'],
      'sub': data['sub'],
    });
    return jwt.sign(
        djwt.RSAPrivateKey(
            bu.CryptoUtils.encodeRSAPrivateKeyToPem(data['privateKey'])),
        algorithm: djwt.JWTAlgorithm.RS256,
        expiresIn: data['expiresIn'],
        notBefore: Duration.zero);
  }

  ///
  static Future<String> jwtSignRsa(bu.RSAPrivateKey privateKey, int userId,
      String userMail, Duration expiresIn) async {
    return await compute(_jwtSignRsa, {
      'privateKey': privateKey,
      'sub': userId,
      'iss': userMail,
      'expiresIn': expiresIn
    });
  }

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
