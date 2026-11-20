import 'package:flutter/material.dart';


class ThemeUtils {
  /// Theme seeded with the per-chat color, or the inherited theme without an override.
  ///
  /// Brightness and Material 3 always follow the global theme.
  static ThemeData chatTheme(BuildContext context, Color? seed) {
    if (seed == null) {
      return Theme.of(context);
    }
    final brightness = Theme.of(context).brightness;
    // Recomputing the tonal palette on every rebuild lands mid-transition.
    final key = Object.hash(seed, brightness);
    return _chatThemes[key] ??= ThemeData.from(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
        useMaterial3: true);
  }

  static final Map<int, ThemeData> _chatThemes = {};
}
