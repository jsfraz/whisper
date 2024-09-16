import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
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

  /// Call API, handle errors and return result.
  static Future<Response?> callApi(
      Future<Response> Function() methodHttpInfo) async {
    try {
      // Try to call the API
      Response response = await methodHttpInfo();
      // Show error
      if (!response.ok) {
        Map<String, dynamic> errorMap = jsonDecode(response.body);
          Fluttertoast.showToast(
              msg: Utils.capitalizeFirstLetter(errorMap['error']),
              backgroundColor: Colors.red);
      }
      return response;
    } catch (e) {
      // Error
      if (e is ApiException) {
        debugPrint(e.toString());
          Fluttertoast.showToast(
              msg: Utils.capitalizeFirstLetter(e.innerException.toString()),
              backgroundColor: Colors.red);
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
