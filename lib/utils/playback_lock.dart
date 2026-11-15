import 'package:flutter/foundation.dart';

/// Only one source may play at a time (voice messages and the video viewer).
///
/// Whoever starts playing claims the lock; every other player pauses itself
/// when the owner changes.
class PlaybackLock {
  PlaybackLock._();

  static final ValueNotifier<Object?> owner = ValueNotifier<Object?>(null);

  static void claim(Object source) => owner.value = source;

  static void release(Object source) {
    if (identical(owner.value, source)) {
      owner.value = null;
    }
  }
}
