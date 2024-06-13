import 'package:flutter/material.dart';

// Disable scroll glow effect https://stackoverflow.com/a/51119796/19371130
class NoGlowBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
