import 'dart:convert';

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

  test('sign nonce by RSA private key', () async {
    var keyPair = await CryptoUtils.getRSAKeyPair();
    debugPrint('${bu.CryptoUtils.encodeRSAPublicKeyToPem(keyPair.publicKey as bu.RSAPublicKey)}\n');
    Uint8List nonce = CryptoUtils.generateNonce(256);
    debugPrint('${base64Encode(nonce)}\n');
    Uint8List signedNonce = await CryptoUtils.rsaSignNonce(nonce, keyPair.privateKey as bu.RSAPrivateKey);
    debugPrint(base64Encode(signedNonce));
  });
}
