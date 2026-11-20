import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../utils/color_utils.dart';

part 'app_theme.g.dart';

@HiveType(typeId: 2)
class AppTheme {
  /// Constructor for Hive
  AppTheme(this.themeModeStr, this.colorHex);

  @HiveField(0)
  String themeModeStr; // String of ThemeMode enum
  @HiveField(1)
  String colorHex; // Color hex

  /// Factory constructor for user friendly usage
  factory AppTheme.fromValues(ThemeMode themeMode, Color color) {
    return AppTheme(themeMode.name, ColorUtils.colorToHex(color));
  }

  /// Get ThemeMode from themeModeStr
  ThemeMode get themeMode {
    try {
      return ThemeMode.values.byName(themeModeStr);
    } catch (_) {
      themeModeStr = ThemeMode.system.name;
      return ThemeMode.system;
    }
  }

  /// Set ThemeMode to themeModeStr
  set themeMode(ThemeMode value) {
    themeModeStr = value.name;
  }

  /// Get MaterialColor from colorSer
  MaterialColor get color {
    try {
      return ColorUtils.getMaterialColor(ColorUtils.colorFromHex(colorHex));
    } catch (_) {
      color = Colors.blue;
      return Colors.blue;
    }
  }

  /// Set color
  set color(Color value) {
    colorHex = ColorUtils.colorToHex(value);
  }
}
