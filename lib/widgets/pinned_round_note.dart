import 'package:flutter/material.dart';

import '../utils/round_note_playback.dart';
import 'round_note_circle.dart';

/// The playing note as it looks once its circle leaves the chat's viewport:
/// the same player, 48 dp, hanging under the pinned-message strip.
///
/// Tap pauses (and resumes) the note; a horizontal swipe throws the copy away
/// and stops playback. The circle it renders is the same widget the inline note
/// uses, so moving between the two never restarts the video.
class PinnedRoundNote extends StatelessWidget {
  const PinnedRoundNote({required this.playback, this.size = 144, super.key});

  final RoundNotePlayback playback;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final controller = playback.controller;
        if (!playback.pinned ||
            controller == null ||
            !controller.value.isInitialized) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTap: playback.toggle,
          onHorizontalDragEnd: (_) => playback.dismiss(),
          child: Material(
            elevation: 6,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            color: Colors.black,
            child: RoundNoteCircle(
              controller: controller,
              size: size,
              showTime: false,
            ),
          ),
        );
      },
    );
  }
}
