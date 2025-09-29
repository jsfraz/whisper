import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:whisper/utils/crypto_utils.dart';

void main() async {
  test('generate RSA keypair asynchronously', () async {
      var keyPair = await CryptoUtils.getRSAKeyPair();
      debugPrint('${bu.CryptoUtils.encodeRSAPublicKeyToPem(keyPair.publicKey as bu.RSAPublicKey)}\n');
      debugPrint('${bu.CryptoUtils.encodeRSAPrivateKeyToPem(keyPair.privateKey as bu.RSAPrivateKey)}\n');
  });

  test('generate JWT token', () async {
    var keyPair = await CryptoUtils.getRSAKeyPair();
    final token = await CryptoUtils.generateRsaJwt(1, keyPair.privateKey as bu.RSAPrivateKey);
    debugPrint(token);
  });
}
