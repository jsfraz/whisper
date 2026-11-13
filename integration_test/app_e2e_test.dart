import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pointycastle/export.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper/utils/crypto_utils.dart';
import 'package:whisper/utils/media_utils.dart';
import 'package:whisper/utils/utils.dart';
import 'package:whisper_openapi_client_dart/api.dart';
import 'package:whisper_websocket_client_dart/models/new_private_message.dart';
import 'package:whisper_websocket_client_dart/models/private_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_response.dart';
import 'package:whisper_websocket_client_dart/ws_client.dart';

import 'fake_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late AsymmetricKeyPair<PublicKey, PrivateKey> keys;

  setUpAll(() async {
    server = await FakeServer.start();
    Directory cacheDir = Directory(await Utils.getCacheDir());
    await cacheDir.create(recursive: true);
    Hive.init(cacheDir.path);
    keys = await CryptoUtils.getRSAKeyPair();
  });

  tearDownAll(() async {
    Box box = await Hive.openBox('hash');
    await box.clear();
    await Hive.close();
    await server.stop();
  });

  ApiClient client(String? accessToken) {
    HttpBearerAuth? auth;
    if (accessToken != null) {
      auth = HttpBearerAuth()..accessToken = accessToken;
    }
    return ApiClient(basePath: server.url, authentication: auth);
  }

  testWidgets('invite registration creates a user', (tester) async {
    final apiClient = client(null);
    final user = await AuthenticationApi(apiClient).createUser(
      createUserInput: CreateUserInput(
        inviteCode: 'i' * 64,
        publicKey: bu.CryptoUtils.encodeRSAPublicKeyToPem(
            keys.publicKey as bu.RSAPublicKey),
        username: 'e2euser',
      ),
    );

    expect(user, isNotNull);
    expect(user!.username, 'e2euser');
    expect(user.id, isNotEmpty);
  });

  testWidgets('login with RSA JWT and refresh', (tester) async {
    final apiClient = client(null);
    final jwt = await CryptoUtils.generateRsaJwt(
        '1', keys.privateKey as bu.RSAPrivateKey);
    final auth = await AuthenticationApi(apiClient).authUser(
      authUserInput: AuthUserInput(token: jwt),
    );

    expect(auth!.accessToken, isNotEmpty);
    expect(auth.refreshToken, isNotEmpty);

    final refreshed = await AuthenticationApi(apiClient).refreshUserAccessToken(
      refreshUserAccessTokenInput:
          RefreshUserAccessTokenInput(refreshToken: auth.refreshToken),
    );
    expect(refreshed!.accessToken, isNotEmpty);
  });

  testWidgets('message is encrypted, sent over WS and decrypted by receiver',
      (tester) async {
    final receiverToken =
        await WebSocketAuthenticationApi(client('access-1')).webSocketAuth();
    final senderToken =
        await WebSocketAuthenticationApi(client('access-2')).webSocketAuth();

    final received = Completer<WsResponse>();
    final receiver = WsClient(server.wsUrl, onReceived: received.complete);
    await receiver.connect(
        receiverToken!.accessToken, const Duration(seconds: 5));
    final sender = WsClient(server.wsUrl);
    await sender.connect(senderToken!.accessToken, const Duration(seconds: 5));

    final encrypted = await CryptoUtils.encryptMessageData(
        Uint8List.fromList(utf8.encode('hello over websocket')),
        keys.publicKey as RSAPublicKey);
    sender.sendMessage(WsMessage.privateMessage(NewPrivateMessage(
      '1',
      encrypted['encryptedData']!,
      encrypted['encryptedKey']!,
      encrypted['nonce']!,
      encrypted['mac']!,
    )));

    final response = await received.future.timeout(const Duration(seconds: 5));
    final message = (response.payload as List<PrivateMessage>).single;
    expect(message.senderId, '2');

    final plaintext = await CryptoUtils.decryptMessageData(
      message.content,
      message.key,
      message.nonce,
      message.mac,
      keys.privateKey as RSAPrivateKey,
    );
    expect(utf8.decode(plaintext), 'hello over websocket');
    sender.disconnect();
    receiver.disconnect();
  });

  testWidgets('media upload sends only ciphertext and receiver decrypts it',
      (tester) async {
    final plaintext = Uint8List.fromList(utf8.encode('top secret attachment'));
    final encrypted = await MediaUtils.encryptForTransport(plaintext);

    final upload = await MediaApi(client('access-1')).uploadMedia(
      http.MultipartFile.fromBytes('file', encrypted.blob,
          filename: 'blob.bin'),
      '2',
    );
    expect(upload!.id, isNotEmpty);

    final download = await http.get(
      Uri.parse('${server.url}/api/media/${upload.id}'),
      headers: {'Authorization': 'Bearer access-2'},
    );
    expect(download.statusCode, 200);
    expect(download.bodyBytes, isNot(equals(plaintext)));
    expect(download.bodyBytes, encrypted.blob);
    expect(await MediaUtils.decryptTransport(download.bodyBytes, encrypted.key),
        plaintext);

    await MediaApi(client('access-2')).confirmMediaDownload(upload.id);
  });

  testWidgets('local password unlocks with a stable derived key',
      (tester) async {
    const password = 'correct horse battery staple';
    await CacheUtils.setPasswordHash(password);

    expect(await CacheUtils.isCorrectPassword(password), isTrue);
    expect(await CacheUtils.isCorrectPassword('wrong password'), isFalse);

    final salt = CryptoUtils.generateSalt();
    final first = await CryptoUtils.pbkdf2(password, salt);
    final second = await CryptoUtils.pbkdf2(password, salt);
    expect(first, second);
  });
}
