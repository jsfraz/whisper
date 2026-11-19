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
import 'package:whisper_websocket_client_dart/models/message_event.dart';
import 'package:whisper_websocket_client_dart/models/read_receipt.dart';
import 'package:whisper_websocket_client_dart/models/synced.dart';
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/private_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_response.dart';
import 'package:whisper_websocket_client_dart/models/ws_response_type.dart';
import 'cache_utils.dart';
import 'chat_sender.dart';
import 'crypto_utils.dart';
import 'media_utils.dart';
import 'message_notifier.dart';
import 'singleton.dart';
import 'text_envelope.dart';
import '../models/private_message.dart' as pm;
import '../models/user.dart';

class Utils {
  /// Localized text for a server error code (the server only sends camelCase
  /// names). An unknown code falls back to a generic message, so the user never
  /// sees a raw identifier.
  static String serverErrorText(String code) {
    if (code.isEmpty) {
      return 'serverError'.tr();
    }
    final text = code.tr();
    return text == code ? 'serverError'.tr() : text;
  }

  /// Error code from a JSON error body ({"error": "someCode"}). Empty when the
  /// body carries no code.
  static String serverErrorCode(String? body) {
    if (body == null || body.isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // Not JSON: nothing to translate.
    }
    return '';
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
          final code = Utils.serverErrorCode(e.message);
          await Fluttertoast.showToast(
              msg: code.isEmpty
                  ? 'httpError'.tr(args: [e.code.toString()])
                  : Utils.serverErrorText(code),
              backgroundColor: Colors.red);
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
    bool toAuth = !hasTokens || !isTokenUsable(profile.refreshToken);

    if (!toAuth && !isTokenUsable(profile.accessToken)) {
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
        // The device id is created once per installation, signed into the
        // login JWT and registered by the server, so it can be revoked.
        final deviceId = await CacheUtils.getOrCreateDeviceId();
        final token = await CryptoUtils.generateRsaJwt(profile.user.id,
            bu.CryptoUtils.rsaPrivateKeyFromPem(profile.privateKey),
            nonce: challenge.challenge, deviceId: deviceId);
        final authResponse = await Utils.callApi(
            () => Singleton().authApi.authUser(
                    authUserInput: AuthUserInput(
                  token: token,
                  deviceId: deviceId,
                  label: CacheUtils.deviceLabel,
                  platform: CacheUtils.devicePlatform,
                )),
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

  /// Claims of a JWT, or null when it cannot be read. Local use only: the
  /// server remains the authority.
  static Map<String, dynamic>? tokenClaims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      return jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Whether a JWT is expired or unreadable.
  static bool isTokenExpired(String token) {
    final payload = tokenClaims(token);
    if (payload == null) {
      return true;
    }
    final exp = payload['exp'];
    if (exp is! int) {
      return false;
    }
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000)
        .isBefore(DateTime.now());
  }

  /// Whether a JWT is accepted by the current server: readable, unexpired and
  /// carrying the token type the server requires. Tokens issued before types
  /// existed are useless even while their expiry is still in the future, so
  /// they must trigger a login instead of failing every request.
  static bool isTokenUsable(String token) {
    if (isTokenExpired(token)) {
      return false;
    }
    final claims = tokenClaims(token);
    return claims != null && claims['typ'] is String;
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

  /// Decrypt, store and optionally announce a batch of messages.
  ///
  /// Live frames are announced (a notification per conversation) and their
  /// older echoes are dropped; history from a sync is stored silently.
  static Future<void> _storeMessages(List<PrivateMessage> messages,
      {required bool notify, bool advanceCursor = false}) async {
    // A tombstone (deleted for everyone) has no ciphertext left. The caller
    // drops the local copy; storing it here would only create an undecryptable
    // placeholder.
    messages = messages
        .where((message) =>
            message.content != null &&
            message.key != null &&
            message.nonce != null &&
            message.mac != null)
        .toList();
    if (messages.isEmpty) {
      return;
    }
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
                      'data': message.content!,
                      'key': message.key!,
                      'nonce': message.nonce!,
                      'mac': message.mac!,
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
          final envelope = MediaUtils.tryParseMediaEnvelope(decryptedMessage);
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
                forwarded: envelope.forwarded,
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
              return (albumMsg, envelope.references, message.peerId);
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
              forwarded: envelope.forwarded,
            );
            return (mediaMsg, [ref], message.peerId);
          }
          // Plain text message (legacy/unchanged path), or a reply that carries
          // its quote in a text envelope.
          final textEnvelope = tryParseTextEnvelope(decryptedMessage);
          final textMsg = pm.PrivateMessage(
              message.senderId,
              textEnvelope?.body ?? utf8.decode(decryptedMessage),
              message.sentAt,
              DateTime.now(),
              false,
              forwarded: textEnvelope?.forwarded ?? false)
            ..setReplyTo(textEnvelope?.reply);
          return (textMsg, const <MediaReference>[], message.peerId);
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
            const <MediaReference>[],
            message.peerId
          );
        }
      });

      final results = await Future.wait(decryptionTasks);

      // Filter out failed decryptions (null values)
      final valid = results
          .whereType<(pm.PrivateMessage, List<MediaReference>, String)>()
          .toList();
      decryptedMessages = valid.map((e) => e.$1).toList();
      for (final (message, refs, _) in valid) {
        if (refs.isNotEmpty) {
          pendingMediaRefs.putIfAbsent(message.senderId, () => []).addAll(refs);
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
    // Self-sent messages are stored locally before sending; dropping the live
    // server echo prevents a duplicate bubble in the debug self-chat. The
    // archive copy is kept, because it is what a fresh device syncs.
    if (notify) {
      decryptedMessages.removeWhere(
          (message) => message.senderId == Singleton().profile.user.id);
    }

    if (decryptedMessages.isEmpty) {
      return;
    }
    // A batch can hold messages from several peers: store each conversation
    // under its own key. The peer id and not the sender is the conversation:
    // an archived message we sent has our own id as the sender.
    final byPeer = <String, List<pm.PrivateMessage>>{};
    final peerOfMessage = <String, String>{};
    final idOfMessage = <String, String>{};
    final editedOfMessage = <String, DateTime?>{};
    for (final message in messages) {
      final key =
          '${message.senderId}|${message.sentAt.toUtc().toIso8601String()}';
      peerOfMessage[key] = message.peerId;
      idOfMessage[key] = message.id;
      editedOfMessage[key] = message.editedAt;
    }
    for (final message in decryptedMessages) {
      final key =
          '${message.senderId}|${message.sentAt.toUtc().toIso8601String()}';
      // The archive id is what a delete on the server needs.
      message.id ??= idOfMessage[key];
      message.editedAt ??= editedOfMessage[key];
      final peer = peerOfMessage[key] ?? message.senderId;
      byPeer.putIfAbsent(peer, () => []).add(message);
    }
    for (final entry in byPeer.entries) {
      await MessageNotifier().addMessages(entry.key, entry.value);
      // Kick off media downloads now that placeholders are persisted.
      for (final ref in pendingMediaRefs[entry.key] ?? const []) {
        // Fire-and-forget; updates the message + notifies on completion.
        MessageNotifier().downloadMediaMessage(entry.key, ref);
      }
    }
    // A live message would otherwise come back on the next sync and overwrite
    // a downloaded attachment with its placeholder. Only live frames may move
    // the cursor: a history page is one conversation and says nothing about
    // the messages of the others.
    if (advanceCursor) {
      var highestSeq = 0;
      for (final message in messages) {
        if (message.seq > highestSeq) {
          highestSeq = message.seq;
        }
      }
      if (highestSeq > 0) {
        await CacheUtils.setSyncSeq(highestSeq);
      }
    }

    if (!notify) {
      return;
    }

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
        decryptedMessages.removeWhere((x) => x.senderId == chatPage.user.id);
      }
    } else {
      // Home page is opened
      homePageOpened = true;
    }
    // Show notification if there are messages to announce and HomePage is not opened
    if (decryptedMessages.isNotEmpty && !homePageOpened) {
      if (Singleton().profile.enableNotifications) {
        await NotificationService().showMessagesNotification(decryptedMessages);
      }
    } else {
      // Vibrate if all messages were for currently opened user
      Vibration.vibrate(pattern: [0, 150], intensities: [0, 255]);
    }
  }

  /// Handle WebSocket message
  static Future<void> onWsMessageReceived(WsResponse wsResponse) async {
    switch (wsResponse.type) {
      // More messages
      case WsResponseType.messages:
        await _storeMessages(wsResponse.payload as List<PrivateMessage>,
            notify: true, advanceCursor: true);
        break;

      // Archive delta after a reconnect
      case WsResponseType.synced:
        final synced = wsResponse.payload as Synced;
        for (final peer in synced.peers) {
          // A fresh device learns the accounts it is talking to from the batch.
          await CacheUtils.addUser(
              User(peer.id, peer.username, peer.publicKey, false));
        }
        // A tombstone carries no ciphertext: drop the local copy instead of
        // storing an undecryptable placeholder.
        for (final dead
            in synced.messages.where((message) => message.deletedAt != null)) {
          await CacheUtils.deletePrivateMessageAt(dead.peerId, dead.sentAt);
        }
        if (synced.messages.isNotEmpty) {
          // History is silent: a week offline must not ring once per old
          // message.
          await _storeMessages(synced.messages, notify: false);
        }
        for (final cleared in synced.cleared) {
          await CacheUtils.applyConversationClearedAt(
              cleared.peerId, cleared.clearedAt.toLocal());
        }
        // Events come after the messages they talk about, which is what the
        // server's cursor ordering guarantees.
        for (final event in synced.events) {
          await applyEvent(event);
        }
        for (final receipt in synced.reads) {
          await CacheUtils.setPeerReadAt(
              receipt.peerId, receipt.readAt.toLocal());
        }
        // Only after the batch is stored: a cursor ahead of the local messages
        // would drop them for good.
        await CacheUtils.setSyncSeq(synced.syncedThrough);
        await CacheUtils.setSyncEventSeq(synced.eventsThrough);
        if (synced.hasMore && Singleton().wsClient.isConnected) {
          Singleton().wsClient.sendSync(synced.syncedThrough,
              sinceEventSeq: synced.eventsThrough);
        }
        break;

      // One live mutation of an archived message
      case WsResponseType.edit:
      case WsResponseType.delete:
      case WsResponseType.reaction:
      case WsResponseType.pin:
        await applyEvent(wsResponse.payload as MessageEvent);
        break;

      // The other participant moved their read cursor
      case WsResponseType.read:
        final receipt = wsResponse.payload as ReadReceipt;
        await CacheUtils.setPeerReadAt(
            receipt.peerId, receipt.readAt.toLocal());
        MessageNotifier().notify();
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
        await ChatSender.confirmSent(ack.receiverId, ack.sentAt, id: ack.id);
        break;

      // Error
      case WsResponseType.error:
        var error = wsResponse.payload as String;
        await Fluttertoast.showToast(
            msg: Utils.serverErrorText(error), backgroundColor: Colors.red);
        break;

      // A frame from a newer server. Ignoring it keeps this build usable.
      case WsResponseType.unknown:
        break;
    }
  }

  /// Applies one entry of the mutation log: an edit, a deletion, a reaction or
  /// a pin of a message this device already has. The same code serves a live
  /// frame and a replayed sync page, so a reconnect converges on the same
  /// state.
  static Future<void> applyEvent(MessageEvent event) async {
    switch (event.kind) {
      case MessageEventKind.delete:
        await CacheUtils.deletePrivateMessageAt(event.peerId, event.sentAt);
        await CacheUtils.setMessagePinned(event.peerId, event.messageId, null);
        break;

      case MessageEventKind.edit:
        final content = event.content;
        if (content == null) {
          return;
        }
        final plain = await _decryptSmall(event);
        if (plain == null) {
          return;
        }
        final body = tryParseTextEnvelope(plain)?.body ?? utf8.decode(plain);
        await CacheUtils.markMessageEdited(
            event.peerId, event.sentAt, body, event.createdAt.toLocal());
        break;

      case MessageEventKind.reaction:
        // My own reaction ciphertext is wrapped for the other side, so this
        // device keeps the emoji it set locally.
        if (event.actorId == Singleton().profile.user.id) {
          return;
        }
        String? emoji;
        if (event.content != null) {
          final plain = await _decryptSmall(event);
          if (plain == null) {
            return;
          }
          emoji = utf8.decode(plain);
        }
        await CacheUtils.setMessageReaction(
            event.peerId, event.sentAt, event.actorId, emoji);
        break;

      case MessageEventKind.pin:
        await CacheUtils.setMessagePinned(event.peerId, event.messageId,
            event.pinned == true ? event.createdAt.toLocal() : null);
        break;
    }
    MessageNotifier().notify();
  }

  /// Decrypts the small payload of an edit or a reaction, null when it cannot
  /// be opened.
  static Future<Uint8List?> _decryptSmall(MessageEvent event) async {
    final content = event.content;
    final key = event.key;
    final nonce = event.nonce;
    final mac = event.mac;
    if (content == null || key == null || nonce == null || mac == null) {
      return null;
    }
    try {
      final decrypted = await CryptoUtils.decryptMessageBatch([
        {'data': content, 'key': key, 'nonce': nonce, 'mac': mac}
      ], Singleton().profile.privateKey);
      return decrypted.single;
    } catch (_) {
      return null;
    }
  }

  /// Decrypt and store a page from the history endpoint.
  ///
  /// History is silent: no notifications and no vibration, the messages are
  /// older than anything the device already has.
  static Future<void> storeHistoryPage(
      List<ModelsPrivateMessage> messages) async {
    if (messages.isEmpty) {
      return;
    }
    // A tombstone carries no ciphertext (the sender deleted it for everyone):
    // drop the local copy instead of storing an undecryptable placeholder.
    for (final dead in messages.where((message) => message.deletedAt != null)) {
      await CacheUtils.deletePrivateMessageAt(dead.peerId, dead.sentAt);
    }
    messages = messages.where((message) => message.deletedAt == null).toList();
    if (messages.isEmpty) {
      return;
    }
    final wire = messages
        .map((message) => PrivateMessage.fromJson({
              'id': message.id,
              'seq': message.seq,
              'senderId': message.senderId,
              'peerId': message.peerId,
              'content': message.content,
              'key': message.key,
              'nonce': message.nonce,
              'mac': message.mac,
              'sentAt': message.sentAt.toIso8601String(),
              'editedAt': message.editedAt?.toIso8601String(),
              'recipientOnline': false,
            }))
        .toList();
    await _storeMessages(wire, notify: false);
  }

  /// Ask the server for the archive delta and the mutation log above the
  /// cursors stored on this device. Nothing is pushed on connect, so this is
  /// what catches a client up.
  static Future<void> syncArchive() async {
    if (!Singleton().wsClient.isConnected) {
      return;
    }
    try {
      Singleton().wsClient.sendSync(await CacheUtils.getSyncSeq(),
          sinceEventSeq: await CacheUtils.getSyncEventSeq());
    } catch (e) {
      if (kDebugMode) {
        debugPrint('sync request failed: $e');
      }
    }
  }

  /// Publishes how far the account has read [peerId]'s chat. Returns false when
  /// the server refused, so the caller can retry on the next message.
  static Future<bool> sendReadCursor(String peerId, DateTime readAt) async {
    try {
      await callApi(
          () => Singleton().chatsApi.setReadCursor(
                peerId,
                setReadCursorInput: SetReadCursorInput(readAt: readAt.toUtc()),
              ),
          rethrowErr: true,
          showError: false);
      return true;
    } catch (_) {
      return false;
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
      // A refused handshake is retried by the backoff loop; a toast per attempt
      // would spam the user of a revoked device.
      var wsAuthResponse = await Utils.callApi(
        () => Singleton().wsAuthApi.webSocketAuth(),
        useSecurity: true,
        showError: false,
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
      // Nothing is pushed on connect: ask for the archive delta above the last
      // seq stored here. A phone away for a week fetches only that week.
      await syncArchive();
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
