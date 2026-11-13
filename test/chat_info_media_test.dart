import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/message_notifier.dart';

PrivateMessage message(String? type, String? path, DateTime sentAt,
    {int? downloadStatus}) {
  return PrivateMessage(1, '', sentAt, sentAt, false,
      mediaTypeStr: type,
      localPath: path,
      downloadStatus: downloadStatus ?? MediaDownloadStatus.ready);
}

void main() {
  test('shared media keeps only ready, viewable media with a local file', () {
    final now = DateTime(2026, 11, 12, 12);
    final media = MessageNotifier.viewableMedia([
      message('image', '/tmp/a.jpg', now),
      message('video', '/tmp/b.mp4', now.subtract(const Duration(minutes: 1))),
      // Voice messages are not part of the overview
      message('voice', '/tmp/c.m4a', now.subtract(const Duration(minutes: 2))),
      // Not downloaded yet
      message('image', null, now.subtract(const Duration(minutes: 3))),
      // Still downloading
      message('image', '/tmp/d.jpg', now.subtract(const Duration(minutes: 4)),
          downloadStatus: MediaDownloadStatus.pending),
      // Plain text
      message(null, null, now.subtract(const Duration(minutes: 5))),
    ]);

    expect(media.map((m) => m.localPath), ['/tmp/a.jpg', '/tmp/b.mp4']);
  });
}
