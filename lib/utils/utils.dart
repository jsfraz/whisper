import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:page_transition/page_transition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';
import '../utils/notification_service.dart';
import '../pages/chat_page.dart';
import 'package:whisper_openapi_client_dart/api.dart';
import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:whisper_websocket_client_dart/models/delivery_ack.dart';
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/private_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_response.dart';
import 'package:whisper_websocket_client_dart/models/ws_response_type.dart';
import 'cache_utils.dart';
import 'chat_sender.dart';
import 'crypto_utils.dart';
import 'media_utils.dart';
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
  ///
  /// [showError] turns the red error toast off for internal calls (token
  /// renewal) that have their own recovery path.
  static Future<T?> callApi<T>(Future<T> Function() call,
      {bool useSecurity = true,
      bool rethrowErr = false,
      bool showError = true}) async {
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
      if (e is ApiException && !showError) {
        if (e.innerException is SocketException) {
          Singleton().offlineMode = true;
        }
      } else if (e is ApiException) {
        if (e.innerException == null) {
          if (e.message != '') {
            Map<String, dynamic> messageMap =
                jsonDecode(e.message!) as Map<String, dynamic>;
            await Fluttertoast.showToast(
                msg: Utils.capitalizeFirstLetter(messageMap['error']),
                backgroundColor: Colors.red);
          } else {
            await Fluttertoast.showToast(
                msg: Utils.capitalizeFirstLetter(
                    'HTTP error ${e.code.toString()}'),
                backgroundColor: Colors.red);
          }
        } else {
          if (e.innerException is SocketException) {
            Singleton().offlineMode = true;
          } else {
            await Fluttertoast.showToast(
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

  /// In-flight token renewal. Concurrent callers (a resume fires several API
  /// calls at once) share one renewal: the refresh token is single use, so two
  /// parallel refreshes would burn the session.
  static Future<void>? _authInFlight;

  /// Checks access and refresh tokens and renews them if necessary.
  ///
  /// A refresh can be refused (session revoked, or a token minted before
  /// sessions were recorded). The RSA challenge always works with the stored
  /// private key, so it is the fallback instead of leaving the app unauthorized.
  static Future<void> authCheck() {
    final inFlight = _authInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final renewal = _doAuthCheck();
    _authInFlight = renewal;
    return renewal.whenComplete(() {
      _authInFlight = null;
    });
  }

  static Future<void> _doAuthCheck() async {
    final profile = Singleton().profile;
    final hasTokens = profile.refreshToken != '' || profile.accessToken != '';
    bool toAuth = !hasTokens || isTokenExpired(profile.refreshToken);

    if (!toAuth && isTokenExpired(profile.accessToken)) {
      var refreshed = false;
      try {
        final refreshResponse = await Utils.callApi(
            () => Singleton().authApi.refreshUserAccessToken(
                refreshUserAccessTokenInput: RefreshUserAccessTokenInput(
                    refreshToken: profile.refreshToken)),
            useSecurity: false,
            rethrowErr: true,
            showError: false);
        if (refreshResponse != null) {
          profile.accessToken = refreshResponse.accessToken;
          // The server rotates the refresh token: the old one is spent.
          if (refreshResponse.refreshToken.isNotEmpty) {
            profile.refreshToken = refreshResponse.refreshToken;
          }
          await CacheUtils.setProfile(profile);
          refreshed = true;
        }
      } on ApiException catch (e) {
        // 401: the server will not renew this session -> log in again.
        if (e.code == 401) {
          toAuth = true;
        }
      } catch (_) {
        // Network problem: stay offline, the next call retries.
      }
      if (!refreshed && !toAuth) {
        Singleton().apiToken = profile.accessToken;
        return;
      }
    }

    if (toAuth) {
      // The server only accepts a login JWT that carries a fresh challenge, so
      // it can never be replayed and a revoked session stays revoked.
      final challenge = await Utils.callApi(
          () => Singleton().authApi.authChallenge(),
          useSecurity: false,
          showError: false);
      if (challenge != null) {
        final token = await CryptoUtils.generateRsaJwt(
            profile.user.id,
            bu.CryptoUtils.rsaPrivateKeyFromPem(profile.privateKey),
            nonce: challenge.challenge);
        final authResponse = await Utils.callApi(
            () => Singleton().authApi.authUser(
                authUserInput: AuthUserInput(token: token)),
            useSecurity: false,
            showError: false);
        if (authResponse != null) {
          profile.accessToken = authResponse.accessToken;
          profile.refreshToken = authResponse.refreshToken;
          await CacheUtils.setProfile(profile);
        }
      }
    }

    // Set API token
    Singleton().apiToken = profile.accessToken;
  }

  /// Whether a JWT is expired or unreadable.
  ///
  /// A local convenience only: the server remains the authority. Replaces the
  /// jwt_decoder dependency, which was used for this single check.
  static bool isTokenExpired(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return true;
    }
    try {
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) {
        return false;
      }
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          .isBefore(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  /// Whether a server URL may be used.
  ///
  /// Release builds only talk to HTTPS: message bodies stay end-to-end
  /// encrypted, but tokens, contacts and metadata would travel in clear text
  /// over plain HTTP. Debug builds accept HTTP for local development.
  static bool isAllowedServerUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return false;
    }
    if (uri.scheme == 'https') {
      return true;
    }
    return !kReleaseMode && uri.scheme == 'http';
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
        // Media references of each conversation that still need a download.
        final pendingMediaRefs = <String, List<MediaReference>>{};

        try {
          // One isolate for the whole batch: a per-message decrypt used to
          // cost an RSA key parse and an isolate spawn each.
          List<Uint8List?> decryptedBatch;
          try {
            decryptedBatch = await CryptoUtils.decryptMessageBatch(
                messages
                    .map((message) => {
                          'data': message.content,
                          'key': message.key,
                          'nonce': message.nonce,
                          'mac': message.mac,
                        })
                    .toList(),
                Singleton().profile.privateKey);
          } catch (_) {
            // A batch failure must not drop the messages: they become visible
            // placeholders below instead of disappearing.
            decryptedBatch = List<Uint8List?>.filled(messages.length, null);
          }

          final decryptionTasks = messages.asMap().entries.map((entry) async {
            final index = entry.key;
            final message = entry.value;
            try {
              final decryptedMessage = decryptedBatch[index];
              if (decryptedMessage == null) {
                throw const FormatException('message decryption failed');
              }
              // Media message: decode the envelope and create a placeholder.
              final envelope =
                  MediaUtils.tryParseMediaEnvelope(decryptedMessage);
              if (envelope != null) {
                if (envelope.references.length > 1) {
                  // Album: one bubble, one download per attachment.
                  final albumMsg = pm.PrivateMessage(
                    message.senderId,
                    envelope.caption,
                    message.sentAt,
                    DateTime.now(),
                    false,
                    downloadStatus: pm.MediaDownloadStatus.pending,
                  );
                  albumMsg.setAlbum(envelope.references
                      .map((ref) => pm.AlbumItem(
                            mediaId: ref.mediaId,
                            type: ref.type.name,
                            size: ref.size,
                            width: ref.width,
                            height: ref.height,
                            durationMs: ref.durationMs,
                            fileName: ref.fileName,
                            status: pm.MediaDownloadStatus.pending,
                          ))
                      .toList());
                  return (albumMsg, envelope.references);
                }
                final ref = envelope.references.single;
                final mediaMsg = pm.PrivateMessage(
                  message.senderId,
                  envelope.caption,
                  message.sentAt,
                  DateTime.now(),
                  false,
                  mediaId: ref.mediaId,
                  mediaTypeStr: ref.type.name,
                  mediaSize: ref.size,
                  width: ref.width,
                  height: ref.height,
                  durationMs: ref.durationMs,
                  fileName: ref.fileName,
                  downloadStatus: pm.MediaDownloadStatus.pending,
                );
                return (mediaMsg, [ref]);
              }
              // Plain text message (legacy/unchanged path).
              final textMsg = pm.PrivateMessage(
                  message.senderId,
                  utf8.decode(decryptedMessage),
                  message.sentAt,
                  DateTime.now(),
                  false);
              return (textMsg, const <MediaReference>[]);
            } catch (e) {
              // Log individual message decryption errors
              if (kDebugMode) {
                debugPrint(
                    'Failed to decrypt message from ${message.senderId}: $e');
              }
              // Keep a visible placeholder: dropping the message hides the loss
              // from the user and from the server (which still has the entry).
              return (
                pm.PrivateMessage(
                  message.senderId,
                  pm.PrivateMessage.undecryptableMarker,
                  message.sentAt,
                  DateTime.now(),
                  false,
                ),
                const <MediaReference>[]
              );
            }
          });

          final results = await Future.wait(decryptionTasks);

          // Filter out failed decryptions (null values)
          final valid = results
              .whereType<(pm.PrivateMessage, List<MediaReference>)>()
              .toList();
          decryptedMessages = valid.map((e) => e.$1).toList();
          for (final (message, refs) in valid) {
            if (refs.isNotEmpty) {
              pendingMediaRefs
                  .putIfAbsent(message.senderId, () => [])
                  .addAll(refs);
            }
          }

          // Show toast only if all messages failed to decrypt
          if (decryptedMessages.isEmpty && messages.isNotEmpty) {
            await Fluttertoast.showToast(
                msg: 'decryptionFailed'.tr(), backgroundColor: Colors.red);
          }
        } catch (_) {
          await Fluttertoast.showToast(
              msg: 'decryptionFailed'.tr(), backgroundColor: Colors.red);
        }
        // Self-sent messages are stored locally before sending; dropping the
        // server echo prevents a duplicate bubble in the debug self-chat.
        decryptedMessages.removeWhere(
            (message) => message.senderId == Singleton().profile.user.id);

        if (decryptedMessages.isNotEmpty) {
          // A batch can hold messages from several senders: store each
          // conversation under its own key.
          final bySender = <String, List<pm.PrivateMessage>>{};
          for (final message in decryptedMessages) {
            bySender.putIfAbsent(message.senderId, () => []).add(message);
          }
          for (final entry in bySender.entries) {
            await MessageNotifier().addMessages(entry.key, entry.value);
            // Kick off media downloads now that placeholders are persisted.
            for (final ref in pendingMediaRefs[entry.key] ?? const []) {
              // Fire-and-forget; updates the message + notifies on completion.
              MessageNotifier().downloadMediaMessage(entry.key, ref);
            }
          }

          // Everything is stored (placeholders included): the server may drop
          // these entries from the offline queue.
          _ackReceived(messages);

          // Remove messages from notifications if user was not online when they were sent
          decryptedMessages.removeWhere((x) => !messages
              .where((y) => y.sentAt == x.sentAt && y.senderId == x.senderId)
              .first
              .recipientOnline);

          bool homePageOpened = false;
          var currentRoute = Singleton().currentRoute;
          if (currentRoute is PageTransition) {
            if (currentRoute.child is ChatPage) {
              var chatPage = currentRoute.child as ChatPage;
              // Delete messages of current open user chat from notifications
              decryptedMessages
                  .removeWhere((x) => x.senderId == chatPage.user.id);
            }
          } else {
            // Home page is opened
            homePageOpened = true;
          }
          // Show notification if there are messages to announce and HomePage is not opened
          if (decryptedMessages.isNotEmpty && !homePageOpened) {
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
        await Fluttertoast.showToast(
            msg: 'accountDeleted2'.tr(), backgroundColor: Colors.red);
        SystemNavigator.pop();
        break;

      // Delivery acknowledgement of one of our outgoing messages
      case WsResponseType.ack:
        final ack = wsResponse.payload as DeliveryAck;
        await ChatSender.confirmSent(ack.receiverId, ack.sentAt);
        break;

      // Error
      case WsResponseType.error:
        var error = wsResponse.payload as String;
        await Fluttertoast.showToast(msg: error, backgroundColor: Colors.red);
        break;
    }
  }

  /// Tells the server the received messages are stored, so it can drop them
  /// from the offline queue. Batched, the server accepts at most 100 per ack.
  static void _ackReceived(List<PrivateMessage> messages) {
    if (messages.isEmpty || !Singleton().wsClient.isConnected) {
      return;
    }
    final acked = messages
        .map((message) => AckedMessage(message.senderId, message.sentAt))
        .toList();
    const batchSize = 100;
    for (var i = 0; i < acked.length; i += batchSize) {
      final end =
          i + batchSize < acked.length ? i + batchSize : acked.length;
      try {
        Singleton()
            .wsClient
            .sendMessage(WsMessage.ack(acked.sublist(i, end)));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('ack failed: $e');
        }
      }
    }
  }

  /// Invoked after a successful connect, e.g. to push a pending Firebase id
  /// without polling.
  static Future<void> Function()? onConnected;

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

      // Messages that never got a delivery ack are retried now; the server
      // deduplicates them by (receiver, sentAt).
      await ChatSender.resendPending();
      final onConnected = Utils.onConnected;
      if (onConnected != null) {
        await onConnected();
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
