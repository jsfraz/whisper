import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:page_transition/page_transition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';
import '../utils/notification_service.dart';
import '../pages/chat_page.dart';
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

  /// Call API, handle errors and return result.
  static Future<T?> callApi<T>(Future<T> Function() call,
      {bool useSecurity = true, bool rethrowErr = false}) async {
    // Check tokens
    if (useSecurity) {
      await authCheck();
    }
    try {
      // Try to call API
      T result = await call();
      Singleton().offlineMode = false;
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
                    'HTTP error ${e.code.toString()}'),
                backgroundColor: Colors.red);
          }
        } else {
          if (e.innerException is SocketException) {
            Singleton().offlineMode = true;
          } else {
            Fluttertoast.showToast(
                msg: e.innerException.toString(), backgroundColor: Colors.red);
          }
        }
      }
      // Rethrow
      if (rethrowErr) {
        rethrow;
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
      // Auth
      final token = await CryptoUtils.generateRsaJwt(
          Singleton().profile.user.id,
          bu.CryptoUtils.rsaPrivateKeyFromPem(Singleton().profile.privateKey));
      var authResponse = await Utils.callApi(
          () => Singleton()
              .authApi
              .authUser(authUserInput: AuthUserInput(token: token)),
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
    switch (wsResponse.type) {
      // More messages
      case WsResponseType.messages:
        var messages = wsResponse.payload as List<PrivateMessage>;
        messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
        List<pm.PrivateMessage> decryptedMessages = [];
        // TODO parallelly decrypt
        for (var message in messages) {
          try {
            var decryptedMessage = await CryptoUtils.rsaDecrypt(
                message.message,
                bu.CryptoUtils.rsaPrivateKeyFromPem(
                    Singleton().profile.privateKey));
            var privateMessage = pm.PrivateMessage(
                message.senderId,
                utf8.decode(decryptedMessage),
                message.sentAt,
                DateTime.now(),
                false);
            decryptedMessages.add(privateMessage);
          } catch (e) {
            Fluttertoast.showToast(
                msg: e.toString(), backgroundColor: Colors.red);
          }
        }
        if (decryptedMessages.isNotEmpty) {
          await MessageNotifier()
              .addMessages(decryptedMessages.first.senderId, decryptedMessages);
          
          // Remove messages from notifications if user was not online when they were sent
          messages.removeWhere((x) => !x.recipientOnline);

          var currentRoute = Singleton().currentRoute;
          if (currentRoute is PageTransition) {
            if (currentRoute.child is ChatPage) {
              var chatPage = currentRoute.child as ChatPage;
              // Delete messages of current open user chat from notifications
              messages.removeWhere((x) => x.senderId == chatPage.user.id);
            }
          }
          // Show notification and vibrate if there are messages to announce
          if (messages.isNotEmpty) {
            Vibration.vibrate(pattern: [0, 150], intensities: [0, 255]);
            if (Singleton().profile.enableNotifications) {
              await NotificationService()
                  .showMessagesNotification(decryptedMessages);
            }
          } else {
            // Vibrate if all messages were for currently opened user
            Vibration.vibrate(pattern: [0, 150], intensities: [0, 255]);
          }
        }
        break;

      // Delete account
      case WsResponseType.deleteAccount:
        await CacheUtils.deleteCache();
        Fluttertoast.showToast(
            msg: 'accountDeleted'.tr(), backgroundColor: Colors.red);
        SystemNavigator.pop();
        break;

      // Error
      case WsResponseType.error:
        var error = wsResponse.payload as String;
        Fluttertoast.showToast(msg: error, backgroundColor: Colors.red);
        break;
    }
  }

  /// Connect to WebSocket with improved connection handling
  static Future<void> wsConnect({bool firstConnect = false}) async {
    // Skip if already connected
    if (Singleton().wsClient.isConnected) {
      // Ensure we're not in offline mode if connected
      if (Singleton().offlineMode) {
        Singleton().offlineMode = false;
      }
      return;
    }

    // Set offline mode immediately if disconnected (except on first connect)
    if (!firstConnect && !Singleton().offlineMode) {
      Singleton().offlineMode = true;
    }

    try {
      // Attempt to get WebSocket access token
      var wsAuthResponse = await Utils.callApi(
        () => Singleton().wsAuthApi.webSocketAuth(),
        useSecurity: true,
      ).timeout(
        Duration(seconds: 10), // Add timeout for API calls
        onTimeout: () => null,
      );

      if (wsAuthResponse?.accessToken != null) {
        // Attempt WebSocket connection
        await _attemptWsConnection(wsAuthResponse!.accessToken);
      } else {
        // API call failed, ensure offline mode
        Singleton().offlineMode = true;
      }
    } catch (e) {
      // Any error during the process
      Singleton().offlineMode = true;
      if (kDebugMode) {
        debugPrint('WebSocket connection failed: $e');
      }
    }
  }

  /// Helper method to attempt WebSocket connection
  static Future<void> _attemptWsConnection(String accessToken) async {
    try {
      await Singleton().wsClient.connect(accessToken, Duration(seconds: 5));
      
      // Connection successful
      Singleton().offlineMode = false;
      
      if (kDebugMode) {
        debugPrint('WebSocket connected successfully');
      }
    } catch (e) {
      // WebSocket connection failed
      Singleton().offlineMode = true;
      
      if (kDebugMode) {
        debugPrint('WebSocket connection attempt failed: $e');
      }
      
      // Optionally disconnect if partially connected
      try {
        Singleton().wsClient.disconnect();
      } catch (_) {
        // Ignore disconnect errors
      }
    }
  }

  /// Get current connection status
  static bool get isOnline => 
    Singleton().wsClient.isConnected && !Singleton().offlineMode;

  /// Force disconnect and set offline mode
  static void forceOfflineMode() {
    try {
      Singleton().wsClient.disconnect();
    } catch (_) {
      // Ignore disconnect errors
    }
    Singleton().offlineMode = true;
  }
}
