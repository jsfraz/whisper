import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' as djwt;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:cryptography/cryptography.dart' as cryptography;

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
    List<int> salt = md5.convert(utf8.encode(password)).bytes;    // TODO Random salt
    final key =
        await pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
    return await key.extractBytes();
  }

  /// Encrypt by RSA public key asynchronously.
  static Future<Uint8List> rsaEncrypt(
      Uint8List message, RSAPublicKey publicKey) async {
    return await compute(
        _rsaEncrypt, {'publicKey': publicKey, 'message': message});
  }

  /// Encrypt by RSA public key synchronously.
  static Uint8List _rsaEncrypt(Map<String, dynamic> data) {
    // Initalizing Cipher
    var cipher = PKCS1Encoding(RSAEngine());
    cipher.init(true, PublicKeyParameter<RSAPublicKey>(data['publicKey']));
    // Encrypting message
    return cipher.process(data['message']);
  }

  /// Decrypt by RSA private key asynchronously.
  static Future<Uint8List> rsaDecrypt(
      Uint8List message, RSAPrivateKey privateKey) async {
    return await compute(
        _rsaDecrypt, {'privateKey': privateKey, 'message': message});
  }

  /// Decrypt by RSA private key synchronously.
  static Uint8List _rsaDecrypt(Map<String, dynamic> data) {
    // Initalizing Cipher
    var cipher = PKCS1Encoding(RSAEngine());
    cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(data['privateKey']));
    // Decrypting message
    return cipher.process(data['message']);
  }

  /// Generates JWT token valid for 5 seconds asynchronously.
  static Future<String> generateRsaJwt(
      int userId, RSAPrivateKey privateKey) async {
    return await compute(
        _generateRsaJwt, {'userId': userId, 'privateKey': privateKey});
  }

  /// Generate JWT token synchronously.
  static String _generateRsaJwt(Map<String, dynamic> data) {
    final jwt = djwt.JWT({'sub': data['userId']});
    Duration expiresIn = Duration(seconds: 5);
    Duration notBefore = Duration.zero;
    return jwt.sign(djwt.RSAPrivateKey.raw(data['privateKey']),
        algorithm: djwt.JWTAlgorithm.RS256,
        expiresIn: expiresIn,
        notBefore: notBefore,
        noIssueAt: false);
  }

  /// Encrypts data using hybrid encryption (RSA + AES)
  static Future<Map<String, Uint8List>> encryptMessageData(
      Uint8List data, RSAPublicKey publicKey) async {
    // Generate a random AES key
    final aesAlgorithm = cryptography.AesGcm.with256bits();
    final secretKey = await aesAlgorithm.newSecretKey();
    final aesKeyBytes = await secretKey.extractBytes();

    // Generate a random nonce (initialization vector)
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(
      Uint8List.fromList(List.generate(32, (i) => Random.secure().nextInt(256))),
    ));
    final nonce = Uint8List.fromList(
        List.generate(12, (_) => secureRandom.nextUint8()));

    // Encrypt data using AES-GCM
    final secretBox = await aesAlgorithm.encrypt(
      data,
      secretKey: secretKey,
      nonce: nonce,
    );

    // Encrypt the AES key using RSA
    final encryptedAesKey = await CryptoUtils.rsaEncrypt(
        Uint8List.fromList(aesKeyBytes), publicKey);

    // Return all the necessary information for decryption
    return {
      'encryptedData': Uint8List.fromList(secretBox.cipherText),
      'encryptedKey': encryptedAesKey,
      'nonce': Uint8List.fromList(secretBox.nonce),
      'mac': Uint8List.fromList(secretBox.mac.bytes),
    };
  }

  /// Decrypts data using hybrid encryption (RSA + AES)
  static Future<Uint8List> decryptMessageData(
      Uint8List encryptedData,
      Uint8List encryptedKey,
      Uint8List nonce,
      Uint8List mac,
      RSAPrivateKey privateKey) async {
    // Decrypt the AES key using RSA
    final aesKeyBytes = await CryptoUtils.rsaDecrypt(encryptedKey, privateKey);

    // Create an AES key from bytes
    final secretKey = cryptography.SecretKey(aesKeyBytes);

    // Decrypt data using AES-GCM
    final aesAlgorithm = cryptography.AesGcm.with256bits();
    final secretBox = cryptography.SecretBox(
      encryptedData,
      nonce: nonce,
      mac: cryptography.Mac(mac),
    );

    return Uint8List.fromList(await aesAlgorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    ));
  }
}
