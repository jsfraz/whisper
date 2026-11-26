import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/utils/cache_utils.dart';
import 'package:shept/utils/message_notifier.dart';
import 'package:shept/utils/utils.dart';
import 'package:shept_websocket_client_dart/models/ws_response.dart';

Uint8List frame(Map<String, dynamic> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// A cursor that arrives with a sync page used to land in Hive without any
/// listener hearing about it, so the ticks of an open chat stayed stale until
/// the next message repainted them.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_read_receipt_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(PrivateMessageAdapter());
    }
  });

  setUp(() async {
    for (final box in [
      'privateMessages',
      'conversations',
      'settings',
      'user'
    ]) {
      await Hive.openBox(box);
      await Hive.box(box).clear();
    }
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('a cursor from a sync page reaches the cache and the UI', () async {
    var notified = 0;
    void listener() => notified++;
    MessageNotifier().addListener(listener);
    addTearDown(() => MessageNotifier().removeListener(listener));

    final readAt = DateTime.utc(2026, 11, 20, 10, 30);
    final response = WsResponse.fromUint8List(frame({
      'type': 'synced',
      'payload': {
        'messages': <dynamic>[],
        'peers': <dynamic>[],
        'events': <dynamic>[],
        'cleared': <dynamic>[],
        'reads': [
          {'v': 1, 'peerId': 'peer-id', 'readAt': readAt.toIso8601String()}
        ],
        'syncedThrough': 0,
        'eventsThrough': 0,
        'hasMore': false,
      },
    }));

    await Utils.onWsMessageReceived(response);

    expect(notified, greaterThan(0));
    expect(await CacheUtils.getPeerReadAt('peer-id'), readAt.toLocal());
  });

  test('the cursor keeps the microseconds of a message sentAt', () async {
    // A read cursor equals the sentAt of the newest message read; rounding it
    // to milliseconds made the message look unread.
    final readAt = DateTime(2026, 11, 20, 10, 30, 0, 123, 456);
    await CacheUtils.setPeerReadAt('a', readAt);
    expect(await CacheUtils.getPeerReadAt('a'), readAt);
  });

  test('a cursor stored in milliseconds still reads', () async {
    final readAt = DateTime(2026, 11, 20, 10, 30, 0, 123);
    final box = await Hive.openBox('conversations');
    await box.put('a', {'peerReadAt': readAt.millisecondsSinceEpoch});
    expect(await CacheUtils.getPeerReadAt('a'), readAt);
  });

  test('the cursor only moves forward and is keyed per peer', () async {
    final later = DateTime(2026, 11, 20, 11);
    await CacheUtils.setPeerReadAt('a', later);
    await CacheUtils.setPeerReadAt(
        'a', later.subtract(const Duration(hours: 1)));
    await CacheUtils.setPeerReadAt('b', later);

    expect(await CacheUtils.getPeerReadAt('a'), later);
    expect(await CacheUtils.getPeerReadAt('b'), later);
  });
}
