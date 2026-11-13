import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper/utils/media_utils.dart';
import 'package:whisper/utils/message_notifier.dart';
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

MediaReference _reference(String id, {MediaType type = MediaType.image}) =>
    MediaReference(
      id,
      Uint8List.fromList(List<int>.generate(32, (i) => i)),
      type,
      1024,
      width: 800,
      height: 600,
      fileName: 'photo.jpg',
    );

void main() {
  group('media envelope', () {
    test('single media keeps the v1 envelope', () {
      final envelope = MediaUtils.buildMediaEnvelope(_reference('m1'), 'hi');
      final parsed = MediaUtils.tryParseMediaEnvelope(envelope);
      expect(parsed, isNotNull);
      expect(parsed!.references.single.mediaId, 'm1');
      expect(parsed.caption, 'hi');
    });

    test('album round trips every reference in order', () {
      final envelope = MediaUtils.buildAlbumEnvelope(
        [_reference('a'), _reference('b'), _reference('c')],
        'album caption',
      );
      final decoded = jsonDecode(utf8.decode(envelope)) as Map;
      expect(decoded['whisperMsg'], MediaUtils.envelopeVersionAlbum);

      final parsed = MediaUtils.tryParseMediaEnvelope(envelope);
      expect(parsed, isNotNull);
      expect(parsed!.references.map((r) => r.mediaId), ['a', 'b', 'c']);
      expect(parsed.caption, 'album caption');
    });

    test('plain text is not an envelope', () {
      final parsed = MediaUtils.tryParseMediaEnvelope(
          Uint8List.fromList(utf8.encode('just text')));
      expect(parsed, isNull);
    });

    test('an unknown envelope version is not parsed', () {
      final parsed = MediaUtils.tryParseMediaEnvelope(Uint8List.fromList(
          utf8.encode('{"whisperMsg":99,"kind":"media","media":[]}')));
      expect(parsed, isNull);
    });
  });

  group('upload limit', () {
    test('accounts for the transport overhead', () {
      expect(MediaUtils.uploadFits(MediaUtils.maxUploadBytes), isFalse);
      expect(
          MediaUtils.uploadFits(
              MediaUtils.maxUploadBytes - MediaUtils.transportOverheadBytes),
          isTrue);
      expect(
          MediaUtils.uploadFits(MediaUtils.maxUploadBytes -
              MediaUtils.transportOverheadBytes +
              1),
          isFalse);
    });
  });

  group('album items', () {
    test('serialize and deserialize', () {
      final message = PrivateMessage('1', 'cap', DateTime(2026), DateTime(2026),
          true);
      message.setAlbum([
        AlbumItem(
          mediaId: 'a',
          type: MediaType.image.name,
          size: 10,
          width: 100,
          height: 50,
          fileName: 'a.jpg',
          localPath: '/tmp/a',
        ),
        AlbumItem(
          mediaId: 'b',
          type: MediaType.video.name,
          size: 20,
          durationMs: 1500,
          status: MediaDownloadStatus.pending,
        ),
      ]);

      expect(message.isAlbum, isTrue);
      expect(message.isMedia, isTrue);
      expect(message.mediaType, isNull);
      final items = message.album;
      expect(items.length, 2);
      expect(items.first.isReady, isTrue);
      expect(items.first.fileName, 'a.jpg');
      expect(items.last.isReady, isFalse);
      expect(items.last.durationMs, 1500);
      expect(message.localPaths, ['/tmp/a']);
    });

    test('expands into one entry per attachment for the viewer', () {
      final message = PrivateMessage('1', 'cap', DateTime(2026), DateTime(2026),
          true);
      message.setAlbum([
        AlbumItem(
            mediaId: 'a',
            type: MediaType.image.name,
            size: 1,
            localPath: '/tmp/a'),
        AlbumItem(
            mediaId: 'b',
            type: MediaType.image.name,
            size: 1,
            localPath: '/tmp/b'),
      ]);

      final expanded = MessageNotifier.albumMedia(message);
      expect(expanded.map((m) => m.mediaId), ['a', 'b']);
      expect(expanded.every((m) => m.localPath != null), isTrue);
      expect(MessageNotifier.viewableMedia([message]).length, 2);
    });
  });

  group('cache', () {
    late Directory dir;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('whisper_album_test');
      Hive.init(dir.path);
      Hive.registerAdapter(PrivateMessageAdapter());
      await Hive.openBox('privateMessages');
      await Hive.box('privateMessages').clear();
    });

    tearDown(() async {
      await Hive.box('privateMessages').clear();
    });

    tearDownAll(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('updating one album attachment keeps the others untouched', () async {
      final message = PrivateMessage('1', 'cap', DateTime(2026, 1, 1),
          DateTime(2026, 1, 1), true,
          downloadStatus: MediaDownloadStatus.pending);
      message.setAlbum([
        AlbumItem(
            mediaId: 'a',
            type: MediaType.image.name,
            size: 1,
            status: MediaDownloadStatus.pending),
        AlbumItem(
            mediaId: 'b',
            type: MediaType.image.name,
            size: 1,
            status: MediaDownloadStatus.pending),
      ]);
      await CacheUtils.addPrivateMessages('1', [message]);

      await CacheUtils.updatePrivateMessageMedia('1', 'b',
          localPath: '/tmp/b', downloadStatus: MediaDownloadStatus.ready);

      final stored = (await CacheUtils.getPrivateMessages('1')).single;
      final items = stored.album;
      expect(items[0].status, MediaDownloadStatus.pending);
      expect(items[0].localPath, isNull);
      expect(items[1].status, MediaDownloadStatus.ready);
      expect(items[1].localPath, '/tmp/b');
      // Not everything is ready yet, so the message stays pending.
      expect(stored.downloadStatus, MediaDownloadStatus.pending);

      await CacheUtils.updatePrivateMessageMedia('1', 'a',
          localPath: '/tmp/a', downloadStatus: MediaDownloadStatus.ready);
      final done = (await CacheUtils.getPrivateMessages('1')).single;
      expect(done.downloadStatus, MediaDownloadStatus.ready);
    });

    test('send status is stored on the message', () async {
      final message = PrivateMessage('1', 'hi', DateTime(2026, 2, 1),
          DateTime(2026, 2, 1), true,
          sendStatus: SendStatus.sending);
      await CacheUtils.addPrivateMessages('1', [message]);
      await CacheUtils.updateStoredMessage('1', message, (stored) {
        stored.sendStatus = SendStatus.sent;
      });
      final stored = (await CacheUtils.getPrivateMessages('1')).single;
      expect(stored.sendStatus, SendStatus.sent);
      await CacheUtils.deletePrivateMessagesWithUser('1');
    });
  });
}
