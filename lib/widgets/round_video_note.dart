import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../utils/cache_utils.dart';
import '../utils/media_autoplay.dart';
import '../utils/media_utils.dart';
import '../utils/playback_lock.dart';

/// A round video note, played in the chat instead of opening the viewer.
///
/// The circle is the note itself: a filling ring runs around it as it plays and
/// the time sits under the picture, the way it looked while recording.
class RoundVideoNote extends StatefulWidget {
  const RoundVideoNote({
    required this.path,
    required this.conversationId,
    required this.sentAt,
    this.size = 200,
    super.key,
  });

  /// The encrypted-at-rest file of the note.
  final String path;

  /// The chat this note lives in, and when it was sent: together they are the
  /// key the next-note chain looks for.
  final String conversationId;
  final DateTime sentAt;

  final double size;

  @override
  State<RoundVideoNote> createState() => _RoundVideoNoteState();
}

class _RoundVideoNoteState extends State<RoundVideoNote>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  File? _tempFile;
  bool _failed = false;

  /// Set once the finished note has asked for the next one, so a repeated
  /// end-of-playback event does not restart the chain.
  bool _chained = false;

  late final String _key =
      CacheUtils.messageKey(widget.conversationId, widget.sentAt);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlaybackLock.owner.addListener(_onLockChanged);
    MediaAutoplay.request.addListener(_onAutoplayRequest);
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final temp = await MediaUtils.materializeTempFile(widget.path, '.mp4');
      final controller = VideoPlayerController.file(temp);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1);
      if (!mounted) {
        await controller.dispose();
        MediaUtils.deleteLocalFile(temp.path);
        return;
      }
      controller.addListener(_onPlayerValue);
      setState(() {
        _tempFile = temp;
        _controller = controller;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  /// Playback ends on its own: park the note at its start so a second tap
  /// replays it, release the playback lock and ask for the next note.
  void _onPlayerValue() {
    final value = _controller?.value;
    if (value == null) {
      return;
    }
    if (value.position >= value.duration && value.duration > Duration.zero) {
      _controller?.pause();
      _controller?.seekTo(Duration.zero);
      PlaybackLock.release(this);
      if (!_chained) {
        _chained = true;
        MediaAutoplay.nextRoundNote(widget.conversationId, widget.sentAt);
      }
    }
  }

  /// Starts this note when the previous one finished and asked for it.
  void _onAutoplayRequest() {
    if (MediaAutoplay.request.value != _key) {
      return;
    }
    MediaAutoplay.request.value = null;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _chained = false;
    PlaybackLock.claim(this);
    controller.play();
  }

  void _onLockChanged() {
    final other = PlaybackLock.owner.value;
    if (other != null &&
        !identical(other, this) &&
        (_controller?.value.isPlaying ?? false)) {
      _controller?.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _controller?.pause();
    }
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      PlaybackLock.release(this);
      return;
    }
    // A tap starts the chain again: the note it plays may have been reached by
    // autoplay before, and that must not stop the next request.
    _chained = false;
    PlaybackLock.claim(this);
    if (controller.value.position >= controller.value.duration) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlaybackLock.owner.removeListener(_onLockChanged);
    MediaAutoplay.request.removeListener(_onAutoplayRequest);
    PlaybackLock.release(this);
    _controller?.removeListener(_onPlayerValue);
    _controller?.dispose();
    final temp = _tempFile;
    if (temp != null) {
      MediaUtils.deleteLocalFile(temp.path);
    }
    super.dispose();
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ring = Theme.of(context).colorScheme.primary;
    if (_failed) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Text('mediaError'.tr(),
              style: TextStyle(color: ring, fontSize: 12)),
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
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds;
        final played = value.position.inMilliseconds.clamp(0, total);
        final progress = total == 0 ? 0.0 : played / total;
        return GestureDetector(
          onTap: _toggle,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            // The indicator draws its stroke inside the box by default, so its
            // outer edge sits 2 dp in. The video is inset by the same 2 dp: the
            // two circles then share one edge instead of the picture peeking
            // past the ring at all four sides.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: ClipOval(
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                  ),
                ),
                // How much of the note is left, as a ring that fills as it plays.
                // Its stroke is centred on a path inset by 4 dp, so the ring's
                // outer edge lands exactly on the video's 98 dp circle: flush
                // with the picture and still inside the bubble's clip.
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 4,
                      strokeAlign: BorderSide.strokeAlignCenter,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.black.withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(ring),
                    ),
                  ),
                ),
                if (!value.isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 30),
                  ),
                Positioned(
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _format(Duration(milliseconds: played)),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
