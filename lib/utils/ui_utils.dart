import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class UiUtils {
  /// Show toast or snackbar based on platform
  static showText(String text, Color color, BuildContext context) {
    // Android/iOS/Fuchsia (Toast)
    if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) {
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
}
