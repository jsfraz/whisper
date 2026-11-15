import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:pointycastle/export.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/profile.dart';
import 'package:whisper/models/user.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper/utils/singleton.dart';
import 'package:whisper/utils/utils.dart';
import 'package:whisper_openapi_client_dart/api.dart';

/// flutter_test replaces HttpClient with one that answers 400 and never touches
/// the network; this test serves its own backend on loopback.
class _RealHttpOverrides extends HttpOverrides {}

/// An unsigned JWT that only has to be readable by the local expiry check.
String tokenExpiring({required Duration inFuture, String typ = 'access'}) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final payload = {
    'sub': 'user',
    'typ': typ,
    'exp': DateTime.now().add(inFuture).millisecondsSinceEpoch ~/ 1000,
  };
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode(payload)}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late HttpServer server;
  late AsymmetricKeyPair<PublicKey, PrivateKey> keys;
  late List<String> requestedPaths;
  const challenge = 'test-challenge-1';

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('whisper_auth_fallback_test');
    Hive.init(dir.path);
    Hive.registerAdapter(ProfileAdapter());
    Hive.registerAdapter(UserAdapter());
    // Not used here, but the box collection is shared with the message tests.
    Hive.registerAdapter(PrivateMessageAdapter());
    // 2048 bits is enough here: the fake server never verifies the signature.
    keys = bu.CryptoUtils.generateRSAKeyPair();

    // path_provider is not registered in a unit test; CacheUtils needs a dir.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
  });

  setUp(() async {
    HttpOverrides.global = _RealHttpOverrides();
    requestedPaths = [];
    Singleton().boxCollectionKey = List<int>.filled(32, 7);
    Singleton().profile = Profile(
      'http://localhost',
      User('user', 'tester', 'public-key', false),
      'public-key',
      bu.CryptoUtils.encodeRSAPrivateKeyToPem(
          keys.privateKey as RSAPrivateKey),
      tokenExpiring(inFuture: const Duration(minutes: 10)),
      tokenExpiring(inFuture: const Duration(days: 6), typ: 'refresh'),
      true,
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  Future<void> startServer({required int refreshStatus}) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/auth/challenge') {
        request.response.statusCode = 200;
        request.response
            .write(jsonEncode({'challenge': challenge, 'expiresIn': 30}));
      } else if (request.uri.path == '/api/auth/refresh') {
        request.response.statusCode = refreshStatus;
        request.response.write(refreshStatus == 200
            ? jsonEncode({
                'accessToken': 'refreshed-access',
                'refreshToken': 'rotated-refresh',
              })
            : jsonEncode({'error': 'refresh session was revoked'}));
      } else if (request.uri.path == '/api/auth') {
        expect(body, contains('token'));
        // The signed login token must carry the one-time challenge.
        final token = (jsonDecode(body) as Map<String, dynamic>)['token']
            as String;
        final payload = jsonDecode(utf8.decode(
                base64Url.decode(base64Url.normalize(token.split('.')[1]))))
            as Map<String, dynamic>;
        expect(payload['nonce'], challenge);
        request.response.statusCode = 200;
        request.response.write(jsonEncode({
          'accessToken': 'fresh-access',
          'refreshToken': 'fresh-refresh',
        }));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'error': 'not found'}));
      }
      await request.response.close();
    });
    Singleton().api =
        ApiClient(basePath: 'http://127.0.0.1:${server.port}');
  }

  test('a refused refresh falls back to the RSA login', () async {
    // The token in the store predates revocable sessions: the server answers
    // 401 and the app used to stay unauthorized forever.
    await startServer(refreshStatus: 401);
    Singleton().profile.accessToken = tokenExpiring(inFuture: Duration.zero);

    await Utils.authCheck();

    expect(requestedPaths, contains('/api/auth/refresh'));
    expect(requestedPaths, contains('/api/auth/challenge'));
    expect(requestedPaths, contains('/api/auth'));
    expect(Singleton().profile.accessToken, 'fresh-access');
    expect(Singleton().profile.refreshToken, 'fresh-refresh');
    expect(Singleton().profile.accessToken, isNot('old-access'));
    expect(Singleton().profile.refreshToken, isNot('legacy-refresh'));
  });

  test('a working refresh does not trigger a full login', () async {
    await startServer(refreshStatus: 200);
    Singleton().profile.accessToken = tokenExpiring(inFuture: Duration.zero);

    await Utils.authCheck();

    expect(requestedPaths, ['/api/auth/refresh']);
    expect(Singleton().profile.accessToken, 'refreshed-access');
    // The server rotates the refresh token; keeping the old one would break the
    // next refresh.
    expect(Singleton().profile.refreshToken, 'rotated-refresh');
  });

  test('concurrent callers share one renewal', () async {
    // The refresh token is single use: two parallel refreshes would burn the
    // session, so a resume must not fan out.
    await startServer(refreshStatus: 200);
    Singleton().profile.accessToken = tokenExpiring(inFuture: Duration.zero);

    await Future.wait([Utils.authCheck(), Utils.authCheck(), Utils.authCheck()]);

    expect(requestedPaths, ['/api/auth/refresh']);
    expect(Singleton().profile.accessToken, 'refreshed-access');
  });

  test('a live access token skips the network entirely', () async {
    await startServer(refreshStatus: 200);
    final accessToken = Singleton().profile.accessToken;

    await Utils.authCheck();

    expect(requestedPaths, isEmpty);
    expect(Singleton().profile.accessToken, accessToken);
  });

  test('the profile survives a restart with the new tokens', () async {
    await startServer(refreshStatus: 401);
    Singleton().profile.accessToken = tokenExpiring(inFuture: Duration.zero);

    await Utils.authCheck();

    final stored = await CacheUtils.getProfile();
    expect(stored.accessToken, 'fresh-access');
    expect(stored.refreshToken, 'fresh-refresh');
  });
}
