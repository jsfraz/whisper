import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Three dots that pulse in sequence, the messenger-style "typing" hint. Only
/// in the tree while the peer is typing, so the animation runs only then; a
/// platform that asks for reduced motion gets a static ellipsis instead.
class TypingDots extends StatefulWidget {
  const TypingDots({this.color, this.dotSize = 6, super.key});

  final Color? color;
  final double dotSize;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final static = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: 'typing'.tr(),
      child: static
          ? Text('…',
              style: TextStyle(
                color: color,
                fontSize: widget.dotSize * 2,
                height: 1,
              ))
          : AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: EdgeInsets.only(right: i == 2 ? 0 : 3),
                      child: _dot(color, i),
                    ),
                ],
              ),
            ),
    );
  }

  /// One dot: a sine bump of opacity and lift, each starting a little later
  /// than the previous one.
  Widget _dot(Color color, int index) {
    final phase = (_controller.value - index * 0.12) % 1.0;
    final bump = math.sin(phase * math.pi);
    return Transform.translate(
      offset: Offset(0, -2 * bump),
      child: Container(
        width: widget.dotSize,
        height: widget.dotSize,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.35 + 0.65 * bump),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
