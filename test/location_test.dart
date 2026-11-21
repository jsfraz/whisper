import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/live_location.dart';
import 'package:whisper/utils/text_envelope.dart';

void main() {
  // A location is a text message with one optional key, so an older client
  // still shows the coordinates instead of raw JSON.
  test('a location survives the text envelope and keeps a text fallback', () {
    const location = LocationRef(50.087, 14.421, accuracy: 12, label: 'Praha');
    final parsed = tryParseTextEnvelope(
        buildTextEnvelope(location.body, null, location: location))!;

    expect(parsed.body, '📍 50.08700, 14.42100');
    expect(parsed.location!.lat, 50.087);
    expect(parsed.location!.lng, 14.421);
    expect(parsed.location!.label, 'Praha');
    expect(parsed.location!.accuracy, 12);
  });

  test('a plain text envelope has no location', () {
    final parsed = tryParseTextEnvelope(buildTextEnvelope('hello', null))!;
    expect(parsed.location, isNull);
  });

  // The relayed position is one string the server cannot read; only the parts
  // have to survive the base64 round trip.
  test('an encrypted payload round-trips through the frame', () {
    final parts = {
      'encryptedData': Uint8List.fromList([1, 2, 3]),
      'encryptedKey': Uint8List.fromList([4, 5]),
      'nonce': Uint8List.fromList([6]),
      'mac': Uint8List.fromList([7, 8]),
    };
    final decoded = decodeEncryptedPayload(encodeEncryptedPayload(parts))!;
    expect(decoded['encryptedData'], [1, 2, 3]);
    expect(decoded['encryptedKey'], [4, 5]);
    expect(decoded['nonce'], [6]);
    expect(decoded['mac'], [7, 8]);
  });

  test('a malformed payload is dropped, not thrown', () {
    expect(decodeEncryptedPayload('not base64!'), isNull);
    expect(
        decodeEncryptedPayload(
            base64Encode(utf8.encode(jsonEncode({'data': 1})))),
        isNull);
  });

  test('a position carries its deadline', () {
    final point = LiveLocationPoint(1.5, 2.5,
        accuracy: 3, until: DateTime.utc(2026, 11, 21, 12));
    final parsed =
        LiveLocationPoint.fromJson(Map<String, dynamic>.from(point.toJson()));
    expect(parsed.lat, 1.5);
    expect(parsed.lng, 2.5);
    expect(parsed.accuracy, 3);
    expect(parsed.until, DateTime.utc(2026, 11, 21, 12));
  });
}
