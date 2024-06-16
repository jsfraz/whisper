import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'is_response_ok.dart';
import 'utils.dart';
import 'package:whisper_openapi_client/api.dart';

class HttpUtils {
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
}
