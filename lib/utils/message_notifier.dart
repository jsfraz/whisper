import 'package:flutter/material.dart';
import 'package:whisper_openapi_client_dart/media_download.dart';
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import '../utils/notification_service.dart';

import '../models/private_message.dart';
import '../models/user.dart';
import 'cache_utils.dart';
import 'media_utils.dart';
import 'singleton.dart';
import 'utils.dart';

class MessageNotifier extends ChangeNotifier {
  /// Singleton instance
  static final MessageNotifier _instance = MessageNotifier._internal();

  factory MessageNotifier() {
    return _instance;
  }

  MessageNotifier._internal();

  /// The media messages of a conversation that the viewer can open, newest
  /// first: a local file, a known type, fully downloaded, not voice. Album
  /// items are expanded into one entry per attachment.
  static List<PrivateMessage> viewableMedia(List<PrivateMessage> messages) {
    final media = <PrivateMessage>[];
    for (final message in messages) {
      if (message.isAlbum) {
        for (final item in albumMedia(message)) {
          if (item.localPath != null &&
              item.mediaType != null &&
              item.mediaType != MediaType.voice &&
              item.downloadStatus == MediaDownloadStatus.ready) {
            media.add(item);
          }
        }
        continue;
      }
      if (message.localPath != null &&
          message.mediaType != null &&
          message.mediaType != MediaType.voice &&
          message.downloadStatus == MediaDownloadStatus.ready) {
        media.add(message);
      }
    }
    media.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return media;
  }

  /// One [PrivateMessage] per album attachment, in album order, so the viewer
  /// and the gallery can treat them like single media messages.
  static List<PrivateMessage> albumMedia(PrivateMessage message) {
    return [
      for (final item in message.album)
        PrivateMessage(
          message.senderId,
          message.message,
          message.sentAt,
          message.receivedAt,
          message.read,
          mediaId: item.mediaId,
          mediaTypeStr: item.type,
          localPath: item.localPath,
          mediaSize: item.size,
          width: item.width,
          height: item.height,
          durationMs: item.durationMs,
          fileName: item.fileName,
          downloadStatus: item.status,
        )
    ];
  }

  /// In-memory map of media references awaiting (or having failed) download,
  /// keyed by media id. The transport key is intentionally never persisted to
  /// disk, so tap-to-retry only works within the current session.
  final Map<String, MediaReference> _pendingMediaRefs = {};

  /// Download, decrypt, store and confirm an incoming media attachment.
  ///
  /// The encrypted file is fetched over HTTP, decrypted with the transport key
  /// from [reference], re-encrypted at rest with the app master key and the
  /// owning message is updated. On success the server copy is confirmed (and
  /// thus deleted); on failure the message is marked as failed for retry.
  Future<void> downloadMediaMessage(
      String conversationUserId, MediaReference reference) async {
    _pendingMediaRefs[reference.mediaId] = reference;
    try {
      final blob = await Utils.callApi(
        () => Singleton().mediaApi.downloadMediaBytes(reference.mediaId),
        rethrowErr: true,
      );
      if (blob == null) {
        throw Exception('empty media download');
      }
      final plaintext = await MediaUtils.decryptTransport(blob, reference.key);
      final localPath = await MediaUtils.encryptAtRest(plaintext);
      await CacheUtils.updatePrivateMessageMedia(
        conversationUserId,
        reference.mediaId,
        localPath: localPath,
        downloadStatus: MediaDownloadStatus.ready,
        // The reference carries the encrypted size; show the real one.
        mediaSize: plaintext.length,
      );
      _pendingMediaRefs.remove(reference.mediaId);
      notifyListeners();
      // Confirm receipt so the server can delete its copy.
      await Utils.callApi(
          () => Singleton().mediaApi.confirmMediaDownload(reference.mediaId));
    } catch (_) {
      await CacheUtils.updatePrivateMessageMedia(
        conversationUserId,
        reference.mediaId,
        downloadStatus: MediaDownloadStatus.failed,
      );
      notifyListeners();
    }
  }

  /// Retry a previously failed media download (current session only).
  Future<void> retryMediaDownload(
      String conversationUserId, String mediaId) async {
    final reference = _pendingMediaRefs[mediaId];
    if (reference == null) {
      return;
    }
    await CacheUtils.updatePrivateMessageMedia(
      conversationUserId,
      mediaId,
      downloadStatus: MediaDownloadStatus.pending,
    );
    notifyListeners();
    await downloadMediaMessage(conversationUserId, reference);
  }

  /// Whether a failed media download can be retried this session.
  bool canRetryMedia(String mediaId) => _pendingMediaRefs.containsKey(mediaId);

  /// Add messages to cache
  Future<void> addMessages(String userId, List<PrivateMessage> messages) async {
    // Check if users exist
    for (var msg in messages) {
      if (!await CacheUtils.userExists(msg.senderId)) {
        var user = await Utils.callApi(
            () => Singleton().userApi.getUserById(msg.senderId));
        if (user != null) {
          // Save user to cache
          await CacheUtils.addUser(User.fromModel(user));
        }
      }
    }
    // Add messages to cache
    await CacheUtils.addPrivateMessages(userId, messages);
    notifyListeners();
  }

  /// Get all messages by user ID
  Future<List<PrivateMessage>> getMessages(String userId) async {
    var messages =
        await CacheUtils.getPrivateMessages(userId, markAsRead: true);
    await NotificationService().removeNotificationsById(
        messages.map((x) => x.notificationId).toList());
    return messages;
  }

  /// Get latest private messages
  Future<Map<User, PrivateMessage>> getLatestPrivateMessages() async {
    var messages = await CacheUtils.getLatestPrivateMessages();
    Map<User, PrivateMessage> newMessages = {};
    // Get missing users
    for (var e in messages.entries) {
      // User does not exists in cache
      if (!e.key.isInBox) {
        var user = await Utils.callApi(
            () => Singleton().userApi.getUserById(e.key.id));
        if (user != null) {
          // Save user to cache
          await CacheUtils.addUser(User.fromModel(user));
          // Get the message for the old user
          var message = messages[e.key];
          // Add new entry with updated user
          newMessages[User.fromModel(user)] = message!;
        }
      } else {
        newMessages[e.key] = e.value;
      }
    }
    // Sort conversations by last message date
    var sortedEntries = newMessages.entries.toList()
      ..sort((a, b) => b.value.receivedAt.compareTo(a.value.receivedAt));
    return Map.fromEntries(sortedEntries);
  }

  /// Delete all chats
  Future<void> deleteAllChats() async {
    await CacheUtils.deleteAllPrivateMessagesWithUsers();
    notifyListeners();
  }

  /// Delete chat by user ID
  Future<void> deleteChat(String userId) async {
    await CacheUtils.deletePrivateMessagesWithUser(userId);
    notifyListeners();
  }

  void notify() {
    notifyListeners();
  }
}
