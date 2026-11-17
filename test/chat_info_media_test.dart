import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/message_notifier.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

PrivateMessage message(String? type, String? path, DateTime sentAt,
    {int? downloadStatus}) {
  return PrivateMessage('1', '', sentAt, sentAt, false,
      mediaTypeStr: type,
      localPath: path,
      downloadStatus: downloadStatus ?? MediaDownloadStatus.ready);
}

PrivateMessage album(DateTime sentAt, String path, MediaType type,
    {int status = MediaDownloadStatus.ready}) {
  final result = PrivateMessage('1', '', sentAt, sentAt, false);
  result.setAlbum([
    AlbumItem(
        mediaId: 'a',
        type: type.name,
        size: 1,
        localPath: path,
        status: status),
  ]);
  return result;
}

void main() {
  test('shared media needs a local file, whatever the status says', () {
    final now = DateTime(2026, 11, 12, 12);
    final media = MessageNotifier.viewableMedia([
      message('image', '/tmp/a.jpg', now),
      message('video', '/tmp/b.mp4', now.subtract(const Duration(minutes: 1))),
      // Voice messages are not part of the overview
      message('voice', '/tmp/c.m4a', now.subtract(const Duration(minutes: 2))),
      // Not downloaded yet
      message('image', null, now.subtract(const Duration(minutes: 3))),
      // Still downloading
      message('image', null, now.subtract(const Duration(minutes: 4)),
          downloadStatus: MediaDownloadStatus.pending),
      // A stale failure flag must not hide a file that is right there
      message('image', '/tmp/e.jpg', now.subtract(const Duration(minutes: 5)),
          downloadStatus: MediaDownloadStatus.expired),
      // Plain text
      message(null, null, now.subtract(const Duration(minutes: 6))),
    ]);

    expect(media.map((m) => m.localPath),
        ['/tmp/a.jpg', '/tmp/b.mp4', '/tmp/e.jpg']);
  });

  test('an album contributes each of its attachments', () {
    final now = DateTime(2026, 11, 12, 12);
    final media = MessageNotifier.viewableMedia([
      album(now, '/tmp/a.jpg', MediaType.image),
      album(now.subtract(const Duration(minutes: 1)), '/tmp/b.mp4',
          MediaType.video,
          status: MediaDownloadStatus.failed),
    ]);

    expect(media.map((m) => m.localPath), ['/tmp/a.jpg', '/tmp/b.mp4']);
    expect(media.first.mediaType, MediaType.image);
  });
}
