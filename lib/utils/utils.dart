import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_openapi_client_dart/api.dart';
import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:whisper_websocket_client_dart/models/private_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_response.dart';
import 'package:whisper_websocket_client_dart/models/ws_response_type.dart';
import 'cache_utils.dart';
import 'crypto_utils.dart';
import 'message_notifier.dart';
import 'singleton.dart';
import '../models/private_message.dart' as pm;

class Utils {
  /// Capitalize first letter of string.
  static String capitalizeFirstLetter(String input) {
    if (input.isEmpty) {
      return input;
    }
    return input[0].toUpperCase() + input.substring(1);
  }

  // TODO offline mode
  /// Call API, handle errors and return result.
  static Future<T?> callApi<T>(Future<T> Function() call,
      {bool useSecurity = true}) async {
    // Check tokens
    if (useSecurity) {
      await authCheck();
    }
    try {
      // Try to call API
      T result = await call();
      return result;
    } catch (e) {
      // Handle error
      if (e is ApiException) {
        if (e.innerException == null) {
          if (e.message != '') {
            Map<String, dynamic> messageMap =
                jsonDecode(e.message!) as Map<String, dynamic>;
            Fluttertoast.showToast(
                msg: Utils.capitalizeFirstLetter(messageMap['error']),
                backgroundColor: Colors.red);
          } else {
            Fluttertoast.showToast(
                msg: Utils.capitalizeFirstLetter(
                    'HTTP error ${e.code.toString()}'), // TODO better code name
                backgroundColor: Colors.red);
          }
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

  /// Checks access and refresh tokens and renews them if necessary.
  static Future<void> authCheck() async {
    bool toAuth = false;
    // Initial auth
    if (Singleton().profile.refreshToken == '' &&
        Singleton().profile.accessToken == '') {
      toAuth = true;
    } else {
      // Auth when refresh token is expired
      toAuth = JwtDecoder.isExpired(Singleton().profile.refreshToken);
    }

    // Auth if necessary
    if (toAuth) {
      // Generate nonce
      Uint8List nonce = CryptoUtils.generateNonce(256);
      // Sign nonce
      Uint8List signedNonce = await CryptoUtils.rsaSignNonce(nonce,
          bu.CryptoUtils.rsaPrivateKeyFromPem(Singleton().profile.privateKey));
      // Auth
      var authResponse = await Utils.callApi(
          () => Singleton().authApi.authUser(
              authUserInput: AuthUserInput(
                  nonce: base64Encode(nonce),
                  signedNonce: base64Encode(signedNonce),
                  userId: Singleton().profile.user.id)),
          useSecurity: false);

      if (authResponse != null) {
        // Set tokens to singleton
        Singleton().profile.accessToken = authResponse.accessToken;
        Singleton().profile.refreshToken = authResponse.refreshToken;
        // Save profile to cache
        await CacheUtils.setProfile(Singleton().profile);
      }
    } else if (JwtDecoder.isExpired(Singleton().profile.accessToken)) {
      // Refresh access token if expired
      var refreshResponse = await Utils.callApi(
          () => Singleton().authApi.refreshUserAccessToken(
              refreshUserAccessTokenInput: RefreshUserAccessTokenInput(
                  refreshToken: Singleton().profile.refreshToken)),
          useSecurity: false);

      if (refreshResponse != null) {
        // Set access token to singleton
        Singleton().profile.accessToken = refreshResponse.accessToken;
        // Save profile to cache
        await CacheUtils.setProfile(Singleton().profile);
      }
    }

    // Set API token
    Singleton().apiToken = Singleton().profile.accessToken;
  }

  /// Get WebSocket URL from APi URL
  static String getWsUrl(String serverUrl) {
    String wsUrl = serverUrl.contains('https')
        ? serverUrl.replaceFirst('https', 'wss')
        : serverUrl.replaceFirst('http', 'ws');
    return '$wsUrl/ws';
  }

  /// Handle WebSocket message
  static Future<void> onWsMessageReceived(WsResponse wsResponse) async {
    var receivedAt = DateTime.now();
    // Print received message
    switch (wsResponse.type) {
      // Message
      case WsResponseType.message:
        var message = wsResponse.payload as PrivateMessage;
        var decryptedMessage = await CryptoUtils.rsaDecrypt(
            message.message,
            bu.CryptoUtils.rsaPrivateKeyFromPem(
                Singleton().profile.privateKey));
        var privateMessage = pm.PrivateMessage(message.senderId,
            utf8.decode(decryptedMessage), message.sentAt, receivedAt);
        await MessageNotifier().addMessages(message.senderId, [privateMessage]);
        break;

      // Error
      case WsResponseType.error:
        var error = wsResponse.payload as String;
        debugPrint(error);
        Fluttertoast.showToast(msg: error, backgroundColor: Colors.red);
        break;
    }
  }
}
