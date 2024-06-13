import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:whisper/utils/is_response_ok.dart';
import 'package:whisper/utils/ui_utils.dart';
import 'package:whisper_openapi_client/api.dart';

class HttpUtils {
  /// Call API, handle errors and return result.
  static Future<Response?> callApi(
      Future<Response> Function() methodHttpInfo, BuildContext context) async {
    try {
      // Try to call the API
      Response response = await methodHttpInfo();
      // Show error
      if (response.ok) {
        // TODO custom status codes
        if (context.mounted) {
          UiUtils.showText("Status ${response.statusCode}",
              Theme.of(context).colorScheme.secondary, context);
        }
      }
      return response;
    } catch (e) {
      // Error
      if (e is ApiException) {
        if (context.mounted) {
          UiUtils.showText(e.innerException.toString(),
              Theme.of(context).colorScheme.secondary, context);
        }
      }
      return null;
    }
  }
}
