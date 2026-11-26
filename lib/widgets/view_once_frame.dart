import 'package:flutter/material.dart';

/// The box a view-once message shows before (and instead of) its content: one
/// icon, one line of state. Tapping it spends the single view; without an
/// [onTap] it is the read-only tombstone.
class ViewOnceFrame extends StatelessWidget {
  const ViewOnceFrame({
    required this.label,
    required this.bubbleColor,
    required this.textColor,
    this.onTap,
    this.dimmed = false,
    super.key,
  });

  final String label;
  final Color bubbleColor;
  final Color textColor;
  final VoidCallback? onTap;

  /// Already opened: the box is drawn fainter, the hue still marks the owner.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // An opened frame is a little duller, never translucent: the peer's colour
    // is already close to the chat background and alpha made it look invisible.
    final fill = dimmed
        ? Color.alphaBlend(scheme.surface.withValues(alpha: 0.35), bubbleColor)
        : bubbleColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off, color: textColor),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
