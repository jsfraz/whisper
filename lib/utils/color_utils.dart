import 'dart:math';
import 'package:flutter/material.dart';

class ColorUtils {

  /// Derives color from username
  static Color getColorFromUsername(String username) {
    // Hash username
    int hash = username.hashCode;
    // Get RGB values from hash
    int red = (hash & 0xFF0000) >> 16; // Upper 8 bits
    int green = (hash & 0x00FF00) >> 8; // Middle 8 bits
    int blue = (hash & 0x0000FF); // Bottom 8 bits
    // Get color
    int minBrightness = 100;
    red = max(red, minBrightness);
    green = max(green, minBrightness);
    blue = max(blue, minBrightness);
    return Color.fromARGB(255, red, green, blue);
  }

  /// Gets contrast color from background color.
  static Color getReadableColor(Color backgroundColor) {
    // RGB to HSV
    final hsvColor = HSVColor.fromColor(backgroundColor);
    // Minimal brightness
    const double minBrightness = 0.3; // Darker than 30%
    // Increase/decrease brightness
    double adjustedValue = hsvColor.value < 0.5
        ? (hsvColor.value + 0.5).clamp(0.0, 1.0)
        : (hsvColor.value - 0.5).clamp(0.0, 1.0);
    // Ensure brightness won't drop below minimum brightness
    adjustedValue =
        adjustedValue < minBrightness ? minBrightness : adjustedValue;
    // Reduce saturation for softer contrast
    final double adjustedSaturation = hsvColor.saturation * 0.7;
    // Creating a new colour with adjusted lightness and saturation
    final newHsvColor =
        hsvColor.withSaturation(adjustedSaturation).withValue(adjustedValue);
    return newHsvColor.toColor();
  }

  // TODO fix deprecation
  /// Color to MaterialColor
  /// https://stackoverflow.com/a/73234955/19371130
  static MaterialColor getMaterialColor(Color color) {
    final int red = color.red;
    final int green = color.green;
    final int blue = color.blue;

    final Map<int, Color> shades = {
      50: Color.fromRGBO(red, green, blue, .1),
      100: Color.fromRGBO(red, green, blue, .2),
      200: Color.fromRGBO(red, green, blue, .3),
      300: Color.fromRGBO(red, green, blue, .4),
      400: Color.fromRGBO(red, green, blue, .5),
      500: Color.fromRGBO(red, green, blue, .6),
      600: Color.fromRGBO(red, green, blue, .7),
      700: Color.fromRGBO(red, green, blue, .8),
      800: Color.fromRGBO(red, green, blue, .9),
      900: Color.fromRGBO(red, green, blue, 1),
    };

    return MaterialColor(color.value, shades);
  }
}
