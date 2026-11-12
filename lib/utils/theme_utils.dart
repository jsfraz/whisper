import 'package:flutter/material.dart';

import 'singleton.dart';

class ThemeUtils {
  /// Theme seeded with the per-chat color, or the inherited theme without an override.
  ///
  /// Brightness and Material 3 always follow the global theme.
  static ThemeData chatTheme(BuildContext context, Color? seed) {
    if (seed == null) {
      return Theme.of(context);
    }
    return ThemeData.from(
        colorScheme: ColorScheme.fromSeed(
            seedColor: seed, brightness: Theme.of(context).brightness),
        useMaterial3: Singleton().appTheme.useMaterial3);
  }
}
