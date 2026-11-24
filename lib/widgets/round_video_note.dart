import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/private_message.dart';
import '../utils/cache_utils.dart';
import '../utils/media_autoplay.dart';
import '../utils/media_utils.dart';
import '../utils/round_note_playback.dart';
import 'round_note_circle.dart';

/// A round video note, played in the chat instead of opening the viewer.
///
/// The circle is the note itself: a filling ring runs around it as it plays and
/// the time sits under the picture, the way it looked while recording. The
/// circle keeps the player; while it is the live note it stays alive after it
/// scrolls out of sight, so the floating copy (`PinnedRoundNote`) can keep
/// rendering the same player.
class RoundVideoNote extends StatefulWidget {
  const RoundVideoNote({
    required this.message,
    required this.conversationId,
    this.size = 200,
    super.key,
  });

  final PrivateMessage message;

  /// The chat this note lives in: with the send time it is the key the chain
  /// and the floating copy look for.
  final String conversationId;

  final double size;

  @override
  State<RoundVideoNote> createState() => _RoundVideoNoteState();
}

class _RoundVideoNoteState extends State<RoundVideoNote>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  File? _tempFile;
  bool _failed = false;

  ScrollableState? _scrollable;
  RoundNotePlayback? _playback;
  bool _reportScheduled = false;

  late final String _key =
      CacheUtils.messageKey(widget.conversationId, widget.message.sentAt);

  bool get _live => _playback?.key == _key;

  bool get playing => _controller?.value.isPlaying ?? false;

  /// How much bigger a playing note is than a resting one. The bubble reserves
  /// the grown size, and 15 % is all the bubble's 16 dp screen inset allows.
  static const double _growth = 1.15;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaAutoplay.request.addListener(_onAutoplayRequest);
    _prepare();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playback = RoundNoteScope.maybeOf(context);
    final scrollable = Scrollable.maybeOf(context);
    if (!identical(scrollable, _scrollable)) {
      _scrollable?.position.removeListener(_scheduleReport);
      _scrollable = scrollable;
      _scrollable?.position.addListener(_scheduleReport);
    }
  }

  /// The circle stays mounted while it is the live note: without that its
  /// player (and the floating copy) would die the moment it leaves the viewport.
  @override
  bool get wantKeepAlive => _live && (_playback?.active ?? false);

  Future<void> _prepare() async {
    try {
      final temp = await MediaUtils.materializeTempFile(
          widget.message.localPath!, '.mp4');
      final controller = VideoPlayerController.file(temp);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1);
      if (!mounted) {
        await controller.dispose();
        MediaUtils.deleteLocalFile(temp.path);
        return;
      }
      setState(() {
        _tempFile = temp;
        _controller = controller;
      });
      _reportVisibility();
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  /// Starts this note when the previous one finished and asked for it.
  void _onAutoplayRequest() {
    if (MediaAutoplay.request.value != _key) {
      return;
    }
    MediaAutoplay.request.value = null;
    _start();
  }

  Future<void> _start() async {
    final controller = _controller;
    final playback = _playback;
    if (controller == null || playback == null) {
      return;
    }
    await playback.start(
      key: _key,
      conversationId: widget.conversationId,
      sentAt: widget.message.sentAt,
      controller: controller,
    );
    updateKeepAlive();
  }

  Future<void> _toggle() async {
    final playback = _playback;
    final controller = _controller;
    if (playback == null || controller == null) {
      return;
    }
    if (_live && controller.value.isPlaying) {
      await playback.pause();
      return;
    }
    await _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return;
    }
    final playback = _playback;
    if (_live && playback != null) {
      playback.pause();
    } else {
      _controller?.pause();
    }
  }

  /// A scroll notification arrives before the frame that moves this note, so
  /// measuring right away reads the old (or detached) box and the floating copy
  /// would stay up after the note came back into sight. Measure after the
  /// frame instead.
  void _scheduleReport() {
    if (_reportScheduled) {
      return;
    }
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (mounted) {
        _reportVisibility();
      }
    });
  }

  /// Reports how much of the circle is on screen; the floating copy appears
  /// once less than half of it is.
  void _reportVisibility() {
    final playback = _playback;
    if (playback == null || playback.key != _key) {
      return;
    }
    final position = _scrollable?.position;
    final box = context.findRenderObject() as RenderBox?;
    final viewport = _scrollable?.context.findRenderObject() as RenderBox?;
    if (box == null ||
        !box.attached ||
        viewport == null ||
        !viewport.attached) {
      playback.updateVisibility(_key, 0);
      return;
    }
    var rect = box.localToGlobal(Offset.zero) & box.size;
    final area = viewport.localToGlobal(Offset.zero) & viewport.size;
    if (position != null) {
      // A rubber band drags the whole list with the finger, so a bounce over the
      // note made the floating copy vanish and come back on release. Measure
      // where the note will sit once the list settles instead.
      final overscroll = position.pixels -
          position.pixels
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (overscroll != 0) {
        final settled = position.axisDirection == AxisDirection.up
            ? overscroll
            : -overscroll;
        rect = rect.shift(Offset(0, -settled));
      }
    }
    playback.updateVisibility(_key, visibleFraction(rect, area));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MediaAutoplay.request.removeListener(_onAutoplayRequest);
    _scrollable?.position.removeListener(_scheduleReport);
    _playback?.detach(_key);
    _controller?.dispose();
    final temp = _tempFile;
    if (temp != null) {
      MediaUtils.deleteLocalFile(temp.path);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = _controller;
    if (_failed) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Text(
            'mediaError'.tr(),
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary, fontSize: 12),
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final playback = _playback;
    // One VideoPlayer per player: while the floating copy shows the video the
    // circle (which is out of sight anyway) keeps only its dark disc.
    final pinned = playback != null && _live && playback.pinned;
    // Reported after every layout: new messages shift the viewport without a
    // scroll event.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reportVisibility();
      }
    });
    return GestureDetector(
      onTap: _toggle,
      child: SizedBox(
        // The bubble always reserves the grown size: a circle that changes the
        // item's height would re-lay the list out under the user's thumb every
        // time a note starts or ends.
        width: widget.size * _growth,
        height: widget.size * _growth,
        child: Center(
          child: TweenAnimationBuilder<double>(
            // The video is a texture: it paints only inside its own layout box,
            // so the growth has to be a real size (a Transform or OverflowBox
            // leaves the picture at 200 dp while the ring moves out).
            tween: Tween<double>(end: _live && playing ? 1 : 1 / _growth),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (context, factor, _) {
              final side = widget.size * _growth * factor;
              return pinned
                  ? ClipOval(
                      child: Container(
                        width: side,
                        height: side,
                        color: Colors.black,
                      ),
                    )
                  : RoundNoteCircle(
                      controller: controller,
                      size: side,
                      showTime: side >= 100,
                    );
            },
          ),
        ),
      ),
    );
  }
}
