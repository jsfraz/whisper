import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_openapi_client/api.dart';

class Utils {
  /// Capitalize first letter of string.
  static String capitalizeFirstLetter(String input) {
    if (input.isEmpty) {
      return input;
    }
    return input[0].toUpperCase() + input.substring(1);
  }

  /// Call API, handle errors and return result.
  static Future<T?> callApi<T>(Future<T> Function() call) async {
    try {
      // Try to call API
      T result = await call();
      return result;
    } catch (e) {
      // Handle error
      if (e is ApiException) {
        if (e.innerException == null) {
          Map<String, dynamic> messageMap =
              jsonDecode(e.message!) as Map<String, dynamic>;
          Fluttertoast.showToast(
              msg: Utils.capitalizeFirstLetter(messageMap['error']),
              backgroundColor: Colors.red);
        } else {
          Fluttertoast.showToast(
              msg: e.innerException.toString(), backgroundColor: Colors.red);
        }
      }
    }
    return null;
  }

  /// Gets cache directory path
  static Future<String> getCacheDir() async {
    Directory dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/whisper';
  }
}
