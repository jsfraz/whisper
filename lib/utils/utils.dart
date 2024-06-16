import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart';
import 'is_response_ok.dart';
import 'package:whisper_openapi_client/api.dart';

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

  /// Call API, handle errors and return result.
  static Future<Response?> callApi(
      Future<Response> Function() methodHttpInfo, BuildContext context) async {
    try {
      // Try to call the API
      Response response = await methodHttpInfo();
      // Show error
      if (!response.ok) {
        Map<String, dynamic> errorMap = jsonDecode(response.body);
        if (context.mounted) {
          Utils.showText(Utils.capitalizeFirstLetter(errorMap['error']),
              Theme.of(context).colorScheme.error, context);
        }
      }
      return response;
    } catch (e) {
      // Error
      if (e is ApiException) {
        if (context.mounted) {
          Utils.showText(e.innerException.toString(),
              Theme.of(context).colorScheme.error, context);
        }
      }
      return null;
    }
  }

  /// Gets cache directory path
  static Future<String> getCacheDir() async {
    Directory dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/whisper';
  }
}
