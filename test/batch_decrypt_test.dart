import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/crypto_utils.dart';

void main() {
  test('album is decoded once per stored json', () {
    final message =
        PrivateMessage('1', '', DateTime.now(), DateTime.now(), false);

    message.setAlbum([
      AlbumItem(mediaId: 'a', type: 'image', size: 1),
    ]);
    final first = message.album;
    expect(first.single.mediaId, 'a');
    // Cached: the same list instance comes back.
    expect(identical(message.album, first), isTrue);

    message.setAlbum([
      AlbumItem(mediaId: 'b', type: 'image', size: 1),
    ]);
    expect(message.album.single.mediaId, 'b');
  });

  test('batch decryption round-trips and keeps failures as null', () async {
    final keyPair = await CryptoUtils.getRSAKeyPair();
    final publicKey = keyPair.publicKey as bu.RSAPublicKey;
    final privateKeyPem = bu.CryptoUtils.encodeRSAPrivateKeyToPem(
        keyPair.privateKey as bu.RSAPrivateKey);

    final payload = Uint8List.fromList(utf8.encode('ahoj'));
    final encrypted = await CryptoUtils.encryptMessageData(payload, publicKey);
    final valid = {
      'data': encrypted['encryptedData']!,
      'key': encrypted['encryptedKey']!,
      'nonce': encrypted['nonce']!,
      'mac': encrypted['mac']!,
    };
    // Same ciphertext with a wrong MAC must fail on its own.
    final broken = {
      ...valid,
      'mac': Uint8List.fromList(List.filled(16, 7)),
    };

    final result =
        await CryptoUtils.decryptMessageBatch([valid, broken], privateKeyPem);

    expect(result, hasLength(2));
    expect(result.first, payload);
    expect(result.last, isNull);
  });
}
