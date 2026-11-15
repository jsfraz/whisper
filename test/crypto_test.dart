import 'dart:convert';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:whisper/utils/crypto_utils.dart';

void main() async {
  test('generate RSA keypair asynchronously', () async {
    var keyPair = await CryptoUtils.getRSAKeyPair();
    debugPrint(
        '${bu.CryptoUtils.encodeRSAPublicKeyToPem(keyPair.publicKey as bu.RSAPublicKey)}\n');
    debugPrint(
        '${bu.CryptoUtils.encodeRSAPrivateKeyToPem(keyPair.privateKey as bu.RSAPrivateKey)}\n');
  });

  test('generate JWT token', () async {
    var keyPair = await CryptoUtils.getRSAKeyPair();
    final token = await CryptoUtils.generateRsaJwt(
        '1', keyPair.privateKey as bu.RSAPrivateKey,
        nonce: 'test-challenge');
    debugPrint(token);
  });

  test('the login token tolerates a server clock behind the phone', () async {
    var keyPair = await CryptoUtils.getRSAKeyPair();
    final token = await CryptoUtils.generateRsaJwt(
        '1', keyPair.privateKey as bu.RSAPrivateKey,
        nonce: 'test-challenge');

    final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))))
        as Map<String, dynamic>;
    final notBefore = DateTime.fromMillisecondsSinceEpoch(
        (payload['nbf'] as int) * 1000);
    // A token whose nbf is "now" is rejected by a server whose clock is a
    // little behind; it must already be valid.
    expect(notBefore.isBefore(DateTime.now()), isTrue);
    expect(notBefore.isAfter(DateTime.now().subtract(const Duration(minutes: 1))),
        isTrue);
  });
}
