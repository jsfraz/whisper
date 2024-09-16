import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:whisper/utils/rsa_utils.dart';

void main() async {
  test('generate RSA keypair asynchronously', () async {
       var keyPair = await RsaUtils.getRSAKeyPair();
      debugPrint(
        CryptoUtils.encodeRSAPublicKeyToPem(keyPair.publicKey as RSAPublicKey));
  });
}
