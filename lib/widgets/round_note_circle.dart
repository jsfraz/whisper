import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The circle of a round note: the video, the ring that fills as it plays, the
/// play badge when it is not playing and, inline only, the running time.
///
/// Shared by the inline note and the floating copy so both keep one geometry:
/// the indicator draws its stroke inside its box by default, so the video is
/// inset by the same 2 dp and the ring's path is inset by its 4 dp stroke -
/// that lands the ring's outer edge exactly on the video's circle instead of on
/// the bubble's clip, which used to shave it flat at all four sides.
class RoundNoteCircle extends StatelessWidget {
  const RoundNoteCircle({
    required this.controller,
    required this.size,
    this.showTime = true,
    super.key,
  });

  final VideoPlayerController controller;
  final double size;

  /// The inline note shows how far it got; the 48 dp copy has no room for it.
  final bool showTime;

  static const double _strokeWidth = 4;

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds;
        final played = value.position.inMilliseconds.clamp(0, total);
        final progress = total == 0 ? 0.0 : played / total;
        return SizedBox(
          width: size,
          height: size,
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
              Padding(
                padding: const EdgeInsets.all(_strokeWidth),
                child: SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: _strokeWidth,
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
                  padding: EdgeInsets.all(size * 0.04),
                  child: Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: size * 0.15,
                  ),
                ),
              if (showTime)
                Positioned(
                  // Just above the video's rim, low enough to read as part of
                  // the note rather than as a caption.
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
        );
      },
    );
  }
}
