import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'media_autoplay.dart';
import 'playback_lock.dart';

/// Whether the note needs its floating copy: it is live (playing, or paused
/// from the copy itself) and mostly out of the chat's viewport.
bool shouldPin({required bool active, required double visibleFraction}) =>
    active && visibleFraction < 0.5;

/// Share of [note] that is inside [viewport]: 0 when it is fully out of sight,
/// 1 when the whole circle is on screen.
double visibleFraction(Rect note, Rect viewport) {
  if (note.height <= 0) {
    return 0;
  }
  final inside = note.intersect(viewport);
  if (inside.height <= 0) {
    return 0;
  }
  return (inside.height / note.height).clamp(0.0, 1.0);
}

/// The note's rect as it will sit once a rubber-band bounce settles: the list
/// follows the finger while stretched, so the stretch is taken out of the
/// measurement and the floating copy does not blink with the bounce.
Rect settledNoteRect(
  Rect note, {
  required double overscroll,
  required bool reversed,
}) =>
    overscroll == 0
        ? note
        : note.shift(Offset(0, reversed ? overscroll : -overscroll));

/// The one round note that is live in the open chat.
///
/// The inline circle keeps owning its player - it is the only thing that can
/// give the note a first frame before it is played - and this holds a reference
/// to it: it says which note is live, how much of it is on screen, and hands
/// the player to the floating copy. The two views therefore never restart the
/// video, and two notes can never play at once.
class RoundNotePlayback extends ChangeNotifier {
  String? _key;
  String? _conversationId;
  DateTime? _sentAt;
  VideoPlayerController? _controller;
  double _visibleFraction = 1;
  bool _active = false;
  bool _chained = false;
  bool _lastPlaying = false;
  bool _disposed = false;

  /// Key of the note that is live, null when nothing is playing any more.
  String? get key => _key;

  /// The player of the live note; the floating copy renders this one.
  VideoPlayerController? get controller => _controller;

  bool get playing => _controller?.value.isPlaying ?? false;

  /// Started and not finished or dismissed yet: the note is still "the one".
  bool get active => _active;

  /// The note is (mostly) out of sight and needs the floating copy.
  bool get pinned =>
      shouldPin(active: _active, visibleFraction: _visibleFraction);

  /// Makes [key] the live note and starts it, resuming a paused one.
  Future<void> start({
    required String key,
    required String conversationId,
    required DateTime sentAt,
    required VideoPlayerController controller,
  }) async {
    if (_key != key || !identical(_controller, controller)) {
      final previous = _controller;
      if (previous != null && !identical(previous, controller)) {
        previous.removeListener(_onValue);
        await previous.pause();
      }
      _key = key;
      _conversationId = conversationId;
      _sentAt = sentAt;
      _controller = controller;
      _visibleFraction = 1;
      _chained = false;
      controller.addListener(_onValue);
    }
    _active = true;
    PlaybackLock.claim(this);
    if (controller.value.position >= controller.value.duration) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
    _notify();
  }

  Future<void> pause() async {
    await _controller?.pause();
    _notify();
  }

  Future<void> resume() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _active = true;
    PlaybackLock.claim(this);
    await controller.play();
    _notify();
  }

  Future<void> toggle() => playing ? pause() : resume();

  /// The floating copy was swiped away: playback stops and the note is no
  /// longer the live one until the user starts it again.
  Future<void> dismiss() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.pause();
    await controller.seekTo(Duration.zero);
    PlaybackLock.release(this);
    _active = false;
    _notify();
  }

  /// How much of [key] is on screen. Only a change of the pin itself is worth a
  /// rebuild: this is called on every scroll frame.
  void updateVisibility(String key, double fraction) {
    if (_key != key) {
      return;
    }
    final wasPinned = pinned;
    _visibleFraction = fraction;
    if (pinned != wasPinned) {
      _notify();
    }
  }

  /// The inline circle is gone: forget the player and stop it.
  void detach(String key) {
    if (_key != key) {
      return;
    }
    final controller = _controller;
    controller?.removeListener(_onValue);
    controller?.pause();
    _controller = null;
    _key = null;
    _active = false;
    _notify();
  }

  void _onValue() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final value = controller.value;
    if (value.position >= value.duration && value.duration > Duration.zero) {
      controller.pause();
      controller.seekTo(Duration.zero);
      PlaybackLock.release(this);
      _active = false;
      // One request per playback: a repeated end-of-video event must not restart
      // the chain.
      if (!_chained) {
        _chained = true;
        MediaAutoplay.nextRoundNote(_conversationId!, _sentAt!);
      }
      _notify();
      return;
    }
    if (value.isPlaying != _lastPlaying) {
      _lastPlaying = value.isPlaying;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.removeListener(_onValue);
    PlaybackLock.release(this);
    super.dispose();
  }
}

/// Gives the chat's [RoundNotePlayback] to the circles inside the list.
class RoundNoteScope extends InheritedNotifier<RoundNotePlayback> {
  const RoundNoteScope({
    required RoundNotePlayback playback,
    required super.child,
    super.key,
  }) : super(notifier: playback);

  static RoundNotePlayback of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoundNoteScope>()!.notifier!;

  static RoundNotePlayback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoundNoteScope>()?.notifier;
}
