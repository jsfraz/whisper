import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/io_client.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:whisper_openapi_client_dart/api.dart';
import 'package:whisper_websocket_client_dart/ws_client.dart';
import '../models/app_theme.dart';
import 'version.dart';
import '../models/profile.dart';
import 'package:flutter/foundation.dart';

/// Singleton https://stackoverflow.com/a/12649574/19371130
class Singleton {
  static final Singleton _singleton = Singleton._internal();

  // OpenAPI client instance
  late ApiClient _api;
  // User profile
  late Profile profile;
  // Box key
  late List<int> boxCollectionKey;
  // App theme
  late AppTheme appTheme;
  // WebSocket client
  late WsClient wsClient;
  // Current route
  late Route currentRoute;
  // Chat a notification tap asked for, opened by HomePage once it is shown
  String? pendingChatUserId;
  // Offline mode
  bool _offlineMode = false;

  factory Singleton() {
    return _singleton;
  }

  Singleton._internal();

  // Setters
  set api(ApiClient api) => _api = api;

  set apiToken(String token) {
    var auth = HttpBearerAuth();
    auth.accessToken = Singleton().profile.accessToken;
    _api = createApiClient(Singleton().profile.url, authentication: auth);
  }

  /// API client with connection and idle timeouts.
  ///
  /// The generated client has no timeout of its own, so a stalled server would
  /// leave a future pending forever (a media bubble stuck on "downloading").
  static ApiClient createApiClient(String basePath,
      {Authentication? authentication}) {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);
    return ApiClient(basePath: basePath, authentication: authentication)
      ..client = IOClient(httpClient)
      // Every request names the app version; the login gate reads it.
      ..addDefaultHeader('X-Client-Version', appVersion);
  }

  set offlineMode(bool offline) {
    if (kDebugMode) {
      if (!_offlineMode && _offlineMode != offline) {
        Fluttertoast.showToast(
            msg: 'offlineTrue'.tr(), backgroundColor: Colors.red);
      }
      if (_offlineMode && _offlineMode != offline) {
        Fluttertoast.showToast(
            msg: 'offlineFalse'.tr(), backgroundColor: Colors.green);
      }
    }
    _offlineMode = offline;
  }

  // Getters
  UserApi get userApi => UserApi(_api);

  AuthenticationApi get authApi => AuthenticationApi(_api);

  InviteApi get inviteApi => InviteApi(_api);

  WebSocketAuthenticationApi get wsAuthApi => WebSocketAuthenticationApi(_api);

  FirebaseApi get firebaseApi => FirebaseApi(_api);

  MediaApi get mediaApi => MediaApi(_api);

  MessagesApi get messagesApi => MessagesApi(_api);

  ChatsApi get chatsApi => ChatsApi(_api);

  bool get offlineMode => _offlineMode;
}
