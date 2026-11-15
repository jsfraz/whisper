import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/private_message.dart';

void main() {
  final sentAt = DateTime(2026, 5, 1);

  test('an undecryptable message is kept as a visible placeholder', () {
    final message = PrivateMessage('peer', PrivateMessage.undecryptableMarker,
        sentAt, DateTime(2026, 5, 1, 0, 1), false);

    expect(message.isUndecryptable, isTrue);
    // The chat list shows the placeholder instead of an empty preview.
    expect(message.preview, isNotEmpty);
  });

  test('a normal message is not mistaken for the placeholder', () {
    final message = PrivateMessage(
        'peer', 'hello', sentAt, DateTime(2026, 5, 1, 0, 1), false);
    expect(message.isUndecryptable, isFalse);
    expect(message.preview, 'hello');
  });

  test('an expired attachment is a terminal state, not a failure', () {
    // Download retries are pointless once the server dropped the file.
    expect(MediaDownloadStatus.expired, isNot(MediaDownloadStatus.failed));
    expect(MediaDownloadStatus.expired, isNot(MediaDownloadStatus.pending));
  });
}
