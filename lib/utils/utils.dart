import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';

class Utils {
  /// Check if device has Android/iOS/Fuchsia.
  static bool isPhone() {
    return Platform.isAndroid || Platform.isIOS || Platform.isFuchsia;
  }

  /// Capitalize first letter of string.
  static String capitalizeFirstLetter(String input) {
    if (input.isEmpty) {
      return input;
    }
    return input[0].toUpperCase() + input.substring(1);
  }

  /// Show toast or snackbar based on platform
  static showText(String text, Color color, BuildContext context) {
    // Toast
    if (Utils.isPhone()) {
      Fluttertoast.showToast(msg: text, backgroundColor: color);
    } else {
      // Snackbar for other platforms
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color.fromARGB(255, 255, 255, 255)),
          ),
          backgroundColor: color));
    }
  }

  /// Gets cache directory path
  static Future<String> getCacheDir() async {
    Directory dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/whisper';
  }
}
