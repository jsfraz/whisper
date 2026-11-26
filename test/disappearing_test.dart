import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/utils/cache_utils.dart';
import 'package:shept/utils/disappearing.dart';
import 'package:shept/utils/media_utils.dart';
import 'package:shept/utils/message_actions.dart';
import 'package:shept/utils/text_envelope.dart';
import 'package:shept_websocket_client_dart/models/media_reference.dart';
import 'package:shept_websocket_client_dart/models/media_type.dart';

PrivateMessage message(String senderId, DateTime sentAt,
    {DateTime? expiresAt, bool viewOnce = false}) {
  return PrivateMessage(senderId, 'text', sentAt, sentAt, true,
      expiresAt: expiresAt, viewOnce: viewOnce);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_disappearing_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
  });

  setUp(() async {
    await Hive.openBox('privateMessages');
    await Hive.box('privateMessages').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('a control message carries its state and timer both ways', () {
    final parsed =
        tryParseSystemEnvelope(buildSystemEnvelope('propose', 86400))!;
    expect(parsed.state, 'propose');
    expect(parsed.seconds, 86400);

    // Anything that is not a control message stays text.
    expect(
        tryParseSystemEnvelope(Uint8List.fromList(utf8.encode('hi'))), isNull);
    expect(
        tryParseSystemEnvelope(Uint8List.fromList(
            utf8.encode(jsonEncode({'kind': 'system', 'state': 'nope'})))),
        isNull);
  });

  test('a view-once flag rides inside the media envelope', () {
    final reference = MediaReference(
        'media-id', Uint8List.fromList([1, 2, 3]), MediaType.image, 3);
    final parsed = MediaUtils.tryParseMediaEnvelope(
        MediaUtils.buildMediaEnvelope(reference, '', viewOnce: true))!;
    expect(parsed.viewOnce, isTrue);
    final plain = MediaUtils.tryParseMediaEnvelope(
        MediaUtils.buildMediaEnvelope(reference, ''))!;
    expect(plain.viewOnce, isFalse);
  });

  // The sweep is what actually removes a disappearing message on this device.
  test('the sweep drops expired rows and keeps the rest', () async {
    final now = DateTime.now();
    await CacheUtils.addPrivateMessages('peer', [
      message('peer', now.subtract(const Duration(hours: 2)),
          expiresAt: now.subtract(const Duration(hours: 1))),
      message('peer', now.subtract(const Duration(minutes: 1)),
          expiresAt: now.add(const Duration(hours: 1))),
      message('peer', now),
    ]);

    expect(await CacheUtils.purgeExpiredMessages(), 1);
    final left = await CacheUtils.getPrivateMessages('peer');
    expect(left.length, 2);
  });

  test('a view-once attachment may not be forwarded', () {
    final now = DateTime.now();
    expect(MessageActions.canForward(message('peer', now, viewOnce: true)),
        isFalse);
    expect(MessageActions.canForward(message('peer', now)), isTrue);
  });

  test('timers are labelled in their own unit', () {
    // No localization is initialised here, so only the numeric labels are
    // asserted; "off" is a translated word.
    expect(disappearingLabel(3600), '1 h');
    expect(disappearingLabel(86400), '1 d');
    expect(disappearingLabel(604800), '7 d');
  });
}
