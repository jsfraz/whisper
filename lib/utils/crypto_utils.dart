import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
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
    secureRandom.seed(KeyParameter(
      Uint8List.fromList(List.generate(32, (i) => i)),
    )); // Seed with random bytes

    return await compute(_getRSAKeyPair, secureRandom);
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

  /// Sign nonce by RSA private key synchronously.
  static Uint8List _rsaSignNonce(Map<String, dynamic> data) {
    final signer = Signer('SHA-256/RSA');
    final rsaPrivateKeyParams =
        PrivateKeyParameter<RSAPrivateKey>(data['privateKey']);
    // Initialize signer with private key
    signer.init(true, rsaPrivateKeyParams);
    // Sign the message
    final signature = signer.generateSignature(data['nonce']) as RSASignature;
    return signature.bytes;
  }

  /// Generate nonce.
  static Uint8List generateNonce(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)));
  }

  /// Sign nonce by RSA private key asynchronously.
  static Future<Uint8List> rsaSignNonce(
      Uint8List nonce, RSAPrivateKey privateKey) async {
    return await compute(
        _rsaSignNonce, {'privateKey': privateKey, 'nonce': nonce});
  }
}
