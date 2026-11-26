import 'package:flutter_test/flutter_test.dart';
import 'package:shept/utils/playback_lock.dart';

void main() {
  test('claim hands the lock to the newest source', () {
    final first = Object();
    final second = Object();
    PlaybackLock.claim(first);
    expect(PlaybackLock.owner.value, same(first));
    PlaybackLock.claim(second);
    expect(PlaybackLock.owner.value, same(second));
  });

  test('release only clears an owned lock', () {
    final owner = Object();
    final stranger = Object();
    PlaybackLock.claim(owner);
    PlaybackLock.release(stranger);
    expect(PlaybackLock.owner.value, same(owner));
    PlaybackLock.release(owner);
    expect(PlaybackLock.owner.value, isNull);
  });
}
