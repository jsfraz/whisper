import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/cache_utils.dart';
import 'package:whisper/utils/media_utils.dart';
import 'package:whisper/utils/message_notifier.dart';
import 'package:whisper/widgets/media_bubble.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

PrivateMessage media(String type, String? path, DateTime sentAt,
    {String? fileName, int size = 1024}) {
  return PrivateMessage('1', '', sentAt, sentAt, false,
      mediaTypeStr: type,
      localPath: path,
      mediaSize: size,
      fileName: fileName,
      downloadStatus: MediaDownloadStatus.ready);
}

void main() {
  group('detectType', () {
    test('documents become files', () {
      expect(MediaUtils.detectType('/tmp/invoice.pdf'), MediaType.file);
      expect(MediaUtils.detectType('/tmp/archive.zip'), MediaType.file);
    });

    test('known media keeps its own type', () {
      expect(MediaUtils.detectType('/tmp/photo.png'), MediaType.image);
      expect(MediaUtils.detectType('/tmp/anim.gif'), MediaType.gif);
      expect(MediaUtils.detectType('/tmp/clip.mp4'), MediaType.video);
      expect(MediaUtils.detectType('/tmp/song.mp3'), MediaType.voice);
    });
  });

  test('baseName keeps the name with its extension', () {
    expect(
        MediaUtils.baseName('/data/user/0/files/invoice.pdf'), 'invoice.pdf');
    expect(MediaUtils.baseName('no-slash.txt'), 'no-slash.txt');
  });

  test('documents get an icon per type', () {
    expect(MediaUtils.iconForFileName('invoice.pdf'), Icons.picture_as_pdf);
    expect(MediaUtils.iconForFileName('report.docx'), Icons.description);
    expect(MediaUtils.iconForFileName('budget.xlsx'), Icons.table_chart);
    expect(MediaUtils.iconForFileName('slides.pptx'), Icons.slideshow);
    expect(MediaUtils.iconForFileName('pack.zip'), Icons.folder_zip);
    expect(MediaUtils.iconForFileName('notes.txt'), Icons.article);
    expect(MediaUtils.iconForFileName('blob'), Icons.insert_drive_file);
    expect(MediaUtils.iconForFileName(null), Icons.insert_drive_file);
  });

  test('sizes are formatted for the bubble', () {
    expect(MediaUtils.formatBytes(512), '512 B');
    expect(MediaUtils.formatBytes(2048), '2.0 KB');
    expect(MediaUtils.formatBytes(3 * 1024 * 1024), '3.0 MB');
  });

  test('a document without a caption previews its name', () {
    final message = media('file', '/tmp/invoice.pdf', DateTime(2026, 11, 13),
        fileName: 'invoice.pdf');
    expect(message.preview, 'invoice.pdf');
    expect(message.mediaType, MediaType.file);
  });

  test('shared media keeps documents, still drops voice', () {
    final now = DateTime(2026, 11, 13, 12);
    final viewable = MessageNotifier.viewableMedia([
      media('file', '/tmp/a.pdf', now, fileName: 'a.pdf'),
      media('voice', '/tmp/b.m4a', now.subtract(const Duration(minutes: 1))),
    ]);
    expect(viewable.map((m) => m.fileName), ['a.pdf']);
  });

  test('the file name survives a Hive round trip', () async {
    final dir = Directory.systemTemp.createTempSync('whisper_file_media_test');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());

    final message =
        media('file', null, DateTime(2026, 11, 13), fileName: 'a.pdf');
    message.mediaId = 'media-1';
    await CacheUtils.addPrivateMessages('7', [message]);
    final stored = await CacheUtils.getPrivateMessages('7');

    expect(stored.single.fileName, 'a.pdf');
    expect(stored.single.mediaTypeStr, 'file');

    // A finished download replaces the encrypted size with the real one
    await CacheUtils.updatePrivateMessageMedia('7', stored.single.mediaId!,
        downloadStatus: MediaDownloadStatus.ready, mediaSize: 4096);
    final updated = await CacheUtils.getPrivateMessages('7');
    expect(updated.single.mediaSize, 4096);

    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  testWidgets('the document bubble shows the name and the size',
      (tester) async {
    final message = media('file', '/tmp/invoice.pdf', DateTime(2026, 11, 13),
        fileName: 'invoice.pdf', size: 2048);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaBubble(
          message: message,
          bubbleColor: Colors.blue,
          textColor: Colors.white,
          onRetry: () {},
          canRetry: false,
          conversationUserId: '1',
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('invoice.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
  });
}
