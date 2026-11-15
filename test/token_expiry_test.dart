import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/utils.dart';

String _token(Map<String, dynamic> payload) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode(payload)}.signature';
}

void main() {
  // Replaces the jwt_decoder dependency, which was only used for this check.
  test('an expired token is detected without a package', () {
    final expired = _token({
      'sub': 'user',
      'exp': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch ~/
          1000,
    });
    expect(Utils.isTokenExpired(expired), isTrue);
  });

  test('a live token is not reported as expired', () {
    final live = _token({
      'sub': 'user',
      'exp': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch ~/
          1000,
    });
    expect(Utils.isTokenExpired(live), isFalse);
  });

  test('a token without the type claim is not usable', () {
    // Issued before the server started requiring `typ`: valid signature and
    // expiry, but every request would be rejected.
    final legacy = _token({
      'sub': 'user',
      'exp': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch ~/
          1000,
    });
    expect(Utils.isTokenExpired(legacy), isFalse);
    expect(Utils.isTokenUsable(legacy), isFalse);
  });

  test('a typed token is usable', () {
    final typed = _token({
      'sub': 'user',
      'typ': 'access',
      'exp': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch ~/
          1000,
    });
    expect(Utils.isTokenUsable(typed), isTrue);
  });

  test('a malformed token counts as expired', () {
    expect(Utils.isTokenExpired(''), isTrue);
    expect(Utils.isTokenExpired('not-a-jwt'), isTrue);
    expect(Utils.isTokenExpired('a.b.c'), isTrue);
  });
}
