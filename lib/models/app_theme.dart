import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../utils/color_utils.dart';

part 'app_theme.g.dart';

@HiveType(typeId: 2)
class AppTheme {
  /// Constructor for Hive
  AppTheme(this.themeModeStr, this.colorHex, this.useMaterial3);

  @HiveField(0)
  String themeModeStr; // String of ThemeMode enum
  @HiveField(1)
  String colorHex; // Color hex
  @HiveField(2)
  bool useMaterial3;

  /// Factory constructor for user friendly usage
  factory AppTheme.fromValues(
      ThemeMode themeMode, Color color, bool material3) {
    return AppTheme(themeMode.name, ColorUtils.colorToHex(color), material3);
  }

  /// Get ThemeMode from themeModeStr
  ThemeMode get themeMode {
    try {
      return ThemeMode.values.byName(themeModeStr);
    } catch (_) {
      return ThemeMode.system;
    }
  }

  /// Set ThemeMode to themeModeStr
  set themeMode(ThemeMode value) {
    themeModeStr = value.name;
  }

  /// Get MaterialColor from colorSer
  MaterialColor get color {
    return ColorUtils.getMaterialColor(ColorUtils.colorFromHex(colorHex));
  }

  /// Set color
  set color(Color value) {
    colorHex = ColorUtils.colorToHex(color);
  }
}
