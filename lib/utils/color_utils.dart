import 'dart:math';
import 'package:flutter/material.dart';

class ColorUtils {

  /// 
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

  /// 
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
}
