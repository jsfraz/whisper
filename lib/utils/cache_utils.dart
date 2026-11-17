import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:bcrypt/bcrypt.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import '../utils/biometric_auth.dart';
import '../models/app_theme.dart';
import '../models/private_message.dart';
import '../models/profile.dart';
import '../models/user.dart';
import 'color_utils.dart';
import 'crypto_utils.dart';
import 'media_utils.dart';
import 'singleton.dart';
import 'utils.dart';

class CacheUtils {
  static const _hashBoxKey = 'hash';
  static const _profileKey = 'profile';
  static const _themeKey = 'theme';
  static const _privateMessagesKey = 'privateMessages';
  static const _userKey = 'user';
  static const _messageConceptKey = 'messageConcept';
  static const _pendingSendsKey = 'pendingSends';
  static const _settingsKey = 'settings';
  static const _notificationPreviewKey = 'notificationPreview';
  static const _biometry = 'biometry';
  static const _playbackSpeed = 'playbackSpeed';
  static const String _saltStorageKey = 'whisper_pbkdf2_salt';
  static const String _deviceIdKey = 'whisper_device_id';
  static const String _syncSeqKey = 'syncSeq';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const _chatThemeKeyPrefix = 'chatTheme:';

  /// Id of this installation, created once and kept in secure storage.
  ///
  /// It is the device the server registers, revokes and reports in the login
  /// JWT. Losing it (a reinstall) is deliberately the same as a new device.
  static Future<String> getOrCreateDeviceId() async {
    final stored = await _secureStorage.read(key: _deviceIdKey);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final id = const Uuid().v4();
    await _secureStorage.write(key: _deviceIdKey, value: id);
    return id;
  }

  /// Human readable name of this platform, shown in the device list.
  static String get deviceLabel {
    if (Platform.isAndroid) {
      return 'Android';
    }
    if (Platform.isIOS) {
      return 'iOS';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    if (Platform.isMacOS) {
      return 'macOS';
    }
    if (Platform.isWindows) {
      return 'Windows';
    }
    return Platform.operatingSystem;
  }

  /// Server platform tag of this installation.
  static String get devicePlatform => Platform.operatingSystem;

  /// Highest archive `seq` stored on this device. A reconnect asks the server
  /// for everything above it instead of receiving a full queue dump.
  static Future<int> getSyncSeq() async {
    Box box = await Hive.openBox(_settingsKey);
    return box.get(_syncSeqKey) as int? ?? 0;
  }

  /// Advances the archive cursor. It never moves backwards: a sync page can
  /// arrive out of order after two overlapping requests.
  static Future<void> setSyncSeq(int seq) async {
    Box box = await Hive.openBox(_settingsKey);
    final stored = box.get(_syncSeqKey) as int? ?? 0;
    if (seq > stored) {
      await box.put(_syncSeqKey, seq);
    }
  }

  /// Opens box with password hash
  static Future<Box> _openPasswordHashBox() async {
    return Hive.openBox(_hashBoxKey);
  }

  /// Sets password hash
  static Future<void> setPasswordHash(String password) async {
    Box box = await _openPasswordHashBox();
    await box.put(_hashBoxKey, BCrypt.hashpw(password, BCrypt.gensalt()));
  }

  /// Returns password hash
  static Future<String?> getPasswordHash() async {
    Box box = await _openPasswordHashBox();
    return box.get(_hashBoxKey);
  }

  /// Checks if the password is correct
  static Future<bool> isCorrectPassword(String password) async {
    String? hash = await getPasswordHash();
    return BCrypt.checkpw(password, hash!);
  }

  /// Returns the PBKDF2 salt, or null for installs created before salts became
  /// random (those still derive it from the password).
  static Future<List<int>?> getSalt() async {
    final String? stored = await _secureStorage.read(key: _saltStorageKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    return base64.decode(stored);
  }

  /// Stores the PBKDF2 salt.
  static Future<void> setSalt(List<int> salt) async {
    await _secureStorage.write(
        key: _saltStorageKey, value: base64.encode(salt));
  }

  /// Opens encrypted box
  static Future<BoxCollection> _openBoxCollection(Set<String> boxNames) async {
    return BoxCollection.open('_encrypted', boxNames,
        path: await Utils.getCacheDir(),
        key: HiveAesCipher(Singleton().boxCollectionKey));
  }

  /// Opens encrypted box without key
  static Future<BoxCollection> _openBoxCollectionWithoutKey(
      Set<String> boxNames) async {
    return BoxCollection.open('_encrypted', boxNames,
        path: await Utils.getCacheDir());
  }

  /// Opens encrypted box
  static Future<CollectionBox> _openBox(String boxName) async {
    BoxCollection collection = await _openBoxCollection({boxName});
    return await collection.openBox(boxName);
  }

  /// Set profile
  static Future<void> setProfile(Profile profile) async {
    CollectionBox box = await _openBox(_profileKey);
    await box.put(_profileKey, profile);
  }

  /// Get profile
  static Future<Profile> getProfile() async {
    CollectionBox box = await _openBox(_profileKey);
    return await box.get(_profileKey);
  }

  /// Delete encrypted cache, password hash and theme from disk
  static Future<void> deleteCache() async {
    BoxCollection collection =
        await _openBoxCollectionWithoutKey({_profileKey});
    await collection.deleteFromDisk();
    Box passwordBox = await _openPasswordHashBox();
    await passwordBox.deleteFromDisk();
    Box themeBox = await _openThemeBox();
    await themeBox.deleteFromDisk();
    await _secureStorage.delete(key: _saltStorageKey);
    Box privateMessagesBox = await _openPrivateMessagesBox();
    await privateMessagesBox.deleteFromDisk();
    Box userBox = await _openUserBox();
    userBox.deleteFromDisk();
    Box messageConceptBox = await _openMessageConceptBox();
    messageConceptBox.deleteFromDisk();
    Box pendingSendsBox = await _openPendingSendsBox();
    pendingSendsBox.deleteFromDisk();
    Box settingsBox = await Hive.openBox(_settingsKey);
    settingsBox.deleteFromDisk();
    if (await isBiometryEnabled()) {
      await BiometricAuth.clearEncryptionKey();
    }
    Box biometryBox = await _openBiometryBox();
    await biometryBox.deleteFromDisk();
    // Remove every locally stored media file.
    await MediaUtils.clearMediaDir();
  }

  /// Opens box with theme
  static Future<Box> _openThemeBox() async {
    return Hive.openBox(_themeKey);
  }

  /// Returns theme
  static Future<AppTheme?> getTheme() async {
    Box box = await _openThemeBox();
    return box.get(_themeKey);
  }

  /// Sets theme
  static Future<void> setTheme(AppTheme theme) async {
    Box box = await _openThemeBox();
    await box.put(_themeKey, theme);
  }

  /// Changes the local password (app lock + at-rest encryption key).
  ///
  /// Returns false when [currentPassword] is wrong. Media files are staged
  /// under the new key first and only swapped in after the profile box has been
  /// rewritten, so a failure leaves the old password valid and the data intact.
  static Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    if (!await isCorrectPassword(currentPassword)) {
      return false;
    }
    final List<int> oldKey = List<int>.from(Singleton().boxCollectionKey);
    final List<int> salt = CryptoUtils.generateSalt();
    final List<int> newKey = await CryptoUtils.pbkdf2(newPassword, salt);
    await _rekeyData(oldKey, newKey);
    await setSalt(salt);
    await setPasswordHash(newPassword);
    return true;
  }

  /// One-time migration from the legacy `md5(password)` salt to a random one.
  /// Returns true when the data was re-encrypted; false when there is nothing
  /// to migrate.
  static Future<bool> migrateSalt(String password) async {
    if (await getSalt() != null) {
      return false;
    }
    if (!await isCorrectPassword(password)) {
      return false;
    }
    final List<int> oldKey = await CryptoUtils.legacyPbkdf2(password);
    final List<int> salt = CryptoUtils.generateSalt();
    final List<int> newKey = await CryptoUtils.pbkdf2(password, salt);
    Singleton().boxCollectionKey = oldKey;
    await _rekeyData(oldKey, newKey);
    await setSalt(salt);
    return true;
  }

  /// Re-encrypts the profile box and every at-rest media file from [oldKey] to
  /// [newKey]. Media is staged first and swapped in only after the profile is
  /// written; the profile box is backed up, so a failure keeps [oldKey] valid.
  static Future<void> _rekeyData(List<int> oldKey, List<int> newKey) async {
    final Profile loaded = await getProfile();
    // A fresh instance: the loaded one is still attached to the box we are
    // about to replace, and Hive refuses to store it in a second box.
    final Profile profile = Profile(
        loaded.url,
        loaded.user,
        loaded.publicKey,
        loaded.privateKey,
        loaded.accessToken,
        loaded.refreshToken,
        loaded.enableNotifications);
    // Hive stores the collection as `<cacheDir>_encrypted/_encrypted_<box>.hive`.
    final File boxFile = File(
        '${await Utils.getCacheDir()}_encrypted/_encrypted_$_profileKey.hive');
    final File backup = File('${boxFile.path}.bak');

    final List<String> staged = await MediaUtils.stageRekey(oldKey, newKey);
    try {
      await Hive.close();
      if (await boxFile.exists()) {
        await boxFile.rename(backup.path);
      }
      Singleton().boxCollectionKey = newKey;
      await setProfile(profile);
    } catch (e) {
      // Roll back to the old key and the old profile box.
      await Hive.close();
      Singleton().boxCollectionKey = oldKey;
      if (await boxFile.exists()) {
        await boxFile.delete();
      }
      if (await backup.exists()) {
        await backup.rename(boxFile.path);
      }
      await MediaUtils.discardRekey(staged);
      rethrow;
    }
    if (await backup.exists()) {
      await backup.delete();
    }
    await MediaUtils.commitRekey(staged);
  }

  /// Returns per-chat theme color, null means the global theme is used
  static Future<Color?> getChatTheme(String userId) async {
    Box box = await _openThemeBox();
    String? hex = box.get('$_chatThemeKeyPrefix$userId');
    return hex == null ? null : ColorUtils.colorFromHex(hex);
  }

  /// Sets per-chat theme color
  static Future<void> setChatTheme(String userId, Color color) async {
    Box box = await _openThemeBox();
    await box.put('$_chatThemeKeyPrefix$userId', ColorUtils.colorToHex(color));
  }

  /// Clears per-chat theme color, the chat falls back to the global theme
  static Future<void> clearChatTheme(String userId) async {
    Box box = await _openThemeBox();
    await box.delete('$_chatThemeKeyPrefix$userId');
  }

  /// Opens box with biometry
  static Future<Box> _openBiometryBox() async {
    return Hive.openBox(_biometry);
  }

  /// Returns biometry
  static Future<bool> isBiometryEnabled() async {
    Box box = await _openBiometryBox();
    return box.get(_biometry) ?? false;
  }

  /// Sets biometry
  static Future<void> setBiometryEnabled(bool enabled) async {
    Box box = await _openBiometryBox();
    await box.put(_biometry, enabled);
  }

  /// Whether notifications may show the decrypted message text. Default off:
  /// the text stays hidden until the user opts in.
  static Future<bool> getNotificationPreview() async {
    Box box = await Hive.openBox(_settingsKey);
    return box.get(_notificationPreviewKey) as bool? ?? false;
  }

  /// Sets whether notifications may show the message text.
  static Future<void> setNotificationPreview(bool value) async {
    Box box = await Hive.openBox(_settingsKey);
    await box.put(_notificationPreviewKey, value);
  }

  /// Opens box with playback preferences
  static Future<Box> _openPlaybackBox() async {
    return Hive.openBox(_playbackSpeed);
  }

  /// Returns the voice message playback speed, 1x until changed
  static Future<double> getPlaybackSpeed() async {
    Box box = await _openPlaybackBox();
    return (box.get(_playbackSpeed) as num?)?.toDouble() ?? 1.0;
  }

  /// Sets the voice message playback speed
  static Future<void> setPlaybackSpeed(double speed) async {
    Box box = await _openPlaybackBox();
    await box.put(_playbackSpeed, speed);
  }

  /// Opens the message box. One key per message, so a write touches one entry
  /// instead of rewriting a whole conversation.
  static Future<Box> _openPrivateMessagesBox() async {
    return Hive.openBox(_privateMessagesKey);
  }

  /// Separates the conversation id from the timestamp in a message key.
  static const String _messageKeySeparator = '|';

  /// Key of one stored message: conversation id plus client timestamp.
  ///
  /// One key per message instead of one list per conversation: adding a message
  /// writes a single entry instead of rewriting the whole chat.
  static String messageKey(String userId, DateTime sentAt) =>
      '$userId$_messageKeySeparator${sentAt.microsecondsSinceEpoch}';

  /// Conversation id of a stored message key, null for legacy keys.
  static String? conversationOfKey(dynamic key) {
    if (key is! String) {
      return null;
    }
    final index = key.lastIndexOf(_messageKeySeparator);
    if (index <= 0) {
      return null;
    }
    return key.substring(0, index);
  }

  static int _timestampOfKey(String key) {
    final index = key.lastIndexOf(_messageKeySeparator);
    return int.tryParse(key.substring(index + 1)) ?? 0;
  }

  /// Keys of one conversation, in box order.
  static Iterable<String> _conversationKeys(Box box, String userId) {
    return box.keys.whereType<String>().where((key) {
      final index = key.lastIndexOf(_messageKeySeparator);
      return index > 0 && key.substring(0, index) == userId;
    });
  }

  /// Older versions stored a whole conversation under the user id. Move those
  /// messages into per-message keys once, then drop the old entry.
  static Future<void> _migrateLegacyConversation(Box box, String userId) async {
    if (!box.containsKey(userId)) {
      return;
    }
    final legacy = box.get(userId);
    if (legacy is List) {
      for (final entry in legacy) {
        if (entry is PrivateMessage) {
          await box.put(messageKey(userId, entry.sentAt), entry);
        }
      }
    }
    await box.delete(userId);
  }

  /// Migrates every legacy conversation entry in the box.
  static Future<void> _migrateLegacyMessages(Box box) async {
    for (final key in box.keys.whereType<String>().toList()) {
      if (conversationOfKey(key) != null) {
        continue;
      }
      await _migrateLegacyConversation(box, key);
    }
  }

  /// Add messages to a conversation.
  ///
  /// A message that is already stored is skipped: the server re-sends
  /// unacknowledged messages, and the stored copy may already carry the read
  /// flag.
  static Future<void> addPrivateMessages(
      String userId, List<PrivateMessage> messages) async {
    Box box = await _openPrivateMessagesBox();
    await _migrateLegacyConversation(box, userId);
    for (final message in messages) {
      final key = messageKey(userId, message.sentAt);
      if (box.containsKey(key)) {
        continue;
      }
      await box.put(key, message);
    }
  }

  /// Get user messages, oldest first, and mark them as read
  static Future<List<PrivateMessage>> getPrivateMessages(String userId,
      {bool markAsRead = false}) async {
    Box box = await _openPrivateMessagesBox();
    await _migrateLegacyConversation(box, userId);
    final entries = <MapEntry<String, PrivateMessage>>[];
    for (final key in _conversationKeys(box, userId)) {
      final value = box.get(key);
      if (value is PrivateMessage) {
        entries.add(MapEntry(key, value));
      }
    }
    entries.sort((a, b) => a.value.sentAt.compareTo(b.value.sentAt));
    // Mark as read, but only write the messages that actually changed: this
    // runs on every chat rebuild.
    for (final entry in entries) {
      if (markAsRead && !entry.value.read) {
        entry.value.read = true;
        await box.put(entry.key, entry.value);
      }
    }
    return entries.map((entry) => entry.value).toList();
  }

  /// Delete a single message locally (and its media file). Nothing is sent to
  /// the server, so the other side keeps the message.
  static Future<void> deletePrivateMessage(
      String userId, PrivateMessage message) async {
    Box box = await _openPrivateMessagesBox();
    await _migrateLegacyConversation(box, userId);
    // Removing the key also removes an emptied conversation from the list.
    await box.delete(messageKey(userId, message.sentAt));
    await _deletePendingSend(userId, message.sentAt);
    for (final path in message.localPaths) {
      await MediaUtils.deleteLocalFile(path);
    }
  }

  /// Delete user messages
  static Future<void> deletePrivateMessagesWithUser(String userId) async {
    Box messageBox = await _openPrivateMessagesBox();
    // Delete on-disk media files for this conversation first.
    await _deleteMediaFilesForUser(userId);
    for (final key in _conversationKeys(messageBox, userId).toList()) {
      await messageBox.delete(key);
    }
    if (messageBox.containsKey(userId)) {
      await messageBox.delete(userId);
    }
    Box userBox = await _openUserBox();
    await userBox.delete(userId);
    await deleteMessageConcept(userId);
    // Pin state goes with the conversation.
    final conversationsBox = await _openConversationsBox();
    await conversationsBox.delete(userId);
  }

  /// Delete the encrypted-at-rest media files of all messages with [userId].
  static Future<void> _deleteMediaFilesForUser(String userId) async {
    final messages = await getPrivateMessages(userId);
    for (final msg in messages) {
      for (final path in msg.localPaths) {
        await MediaUtils.deleteLocalFile(path);
      }
    }
  }

  /// Update the local media state of a stored message (download progress).
  /// [mediaSize] replaces the reference's encrypted size with the real one.
  static Future<void> updatePrivateMessageMedia(String userId, String mediaId,
      {String? localPath, int? downloadStatus, int? mediaSize}) async {
    Box box = await _openPrivateMessagesBox();
    await _migrateLegacyConversation(box, userId);
    final keys = _conversationKeys(box, userId).toList();
    if (keys.isEmpty) {
      return;
    }
    final updated = <String>[];
    for (final key in keys) {
      final dynamic m = box.get(key);
      if (m is! PrivateMessage) {
        continue;
      }
      bool changed = false;
      final msg = m;
      if (msg.mediaId == mediaId) {
        if (localPath != null) {
          msg.localPath = localPath;
        }
        if (downloadStatus != null) {
          msg.downloadStatus = downloadStatus;
        }
        if (mediaSize != null) {
          msg.mediaSize = mediaSize;
        }
        changed = true;
      }
      // Album attachment: update the matching item.
      if (msg.isAlbum) {
        final items = msg.album;
        var itemChanged = false;
        for (final item in items) {
          if (item.mediaId != mediaId) {
            continue;
          }
          if (localPath != null) {
            item.localPath = localPath;
          }
          if (downloadStatus != null) {
            item.status = downloadStatus;
          }
          if (mediaSize != null) {
            item.size = mediaSize;
          }
          itemChanged = true;
        }
        if (itemChanged) {
          msg.setAlbum(items);
          // The message-level flag follows the album, so the bubble can show a
          // single state for "still downloading" vs "done".
          if (downloadStatus != null) {
            final allReady =
                items.every((item) => item.status == MediaDownloadStatus.ready);
            final anyFailed = items.any((item) =>
                item.status == MediaDownloadStatus.failed ||
                item.status == MediaDownloadStatus.expired);
            msg.downloadStatus = allReady
                ? MediaDownloadStatus.ready
                : (anyFailed
                    ? MediaDownloadStatus.failed
                    : MediaDownloadStatus.pending);
          }
          changed = true;
        }
      }
      if (changed) {
        updated.add(key);
      }
    }
    for (final key in updated) {
      final message = box.get(key);
      if (message is PrivateMessage) {
        await box.put(key, message);
      }
    }
  }

  /// Apply [update] to the stored copy of [message] and persist it.
  ///
  /// The message is identified by conversation and client timestamp, the same
  /// identity the delete path and the delivery ack use.
  static Future<void> updateStoredMessage(String userId, PrivateMessage message,
      void Function(PrivateMessage stored) update) async {
    Box box = await _openPrivateMessagesBox();
    await _migrateLegacyConversation(box, userId);
    final key = messageKey(userId, message.sentAt);
    final stored = box.get(key);
    if (stored is! PrivateMessage) {
      return;
    }
    update(stored);
    await box.put(key, stored);
  }

  /// Move a stored message to a fresh client timestamp and key, and return the
  /// stored copy. Used when a failed send is retried too long after it was
  /// written for the server to accept the original timestamp.
  static Future<PrivateMessage?> retimestampMessage(
      String userId, PrivateMessage message) async {
    Box box = await _openPrivateMessagesBox();
    await _migrateLegacyConversation(box, userId);
    final oldKey = messageKey(userId, message.sentAt);
    final stored = box.get(oldKey);
    if (stored is! PrivateMessage) {
      return null;
    }
    final oldSentAt = stored.sentAt;
    // Never collide with the key it already occupies.
    do {
      stored.sentAt = DateTime.now();
    } while (messageKey(userId, stored.sentAt) == oldKey);
    // Hive refuses one object under two keys, so the old entry goes first.
    await box.delete(oldKey);
    await box.put(messageKey(userId, stored.sentAt), stored);
    await _deletePendingSend(userId, oldSentAt);
    return stored;
  }

  /// Marks the message the server acknowledged as sent.

  ///
  /// [receiverId] and [sentAt] are the values the server echoes back; the pair
  /// identifies the stored message without keeping a client message id.
  static Future<void> markMessageSent(
      String receiverId, DateTime sentAt) async {
    Box box = await _openPrivateMessagesBox();
    await _migrateLegacyConversation(box, receiverId);
    final key = messageKey(receiverId, sentAt);
    final stored = box.get(key);
    if (stored is! PrivateMessage) {
      return;
    }
    stored.sendStatus = SendStatus.sent;
    await box.put(key, stored);
    await _deletePendingSend(receiverId, sentAt);
  }

  /// Remembers a message that is waiting for its delivery ack, so a reconnect
  /// can resend exactly those.
  static Future<void> addPendingSend(String receiverId, DateTime sentAt) async {
    Box box = await _openPendingSendsBox();
    await box.put(messageKey(receiverId, sentAt), receiverId);
  }

  static Future<void> _deletePendingSend(
      String receiverId, DateTime sentAt) async {
    Box box = await _openPendingSendsBox();
    await box.delete(messageKey(receiverId, sentAt));
  }

  /// Messages still waiting for a delivery ack, grouped by conversation.
  static Future<Map<String, List<PrivateMessage>>> getPendingSends() async {
    Box pending = await _openPendingSendsBox();
    Box box = await _openPrivateMessagesBox();
    final byConversation = <String, List<PrivateMessage>>{};
    for (final entry in pending.toMap().entries) {
      final key = entry.key;
      if (key is! String) {
        continue;
      }
      final receiverId = entry.value as String;
      final message = box.get(key);
      if (message is! PrivateMessage ||
          message.sendStatus != SendStatus.sending) {
        // Acked, deleted or already given up: forget the marker.
        await pending.delete(key);
        continue;
      }
      byConversation.putIfAbsent(receiverId, () => []).add(message);
    }
    for (final messages in byConversation.values) {
      messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    }
    return byConversation;
  }

  static Future<Box> _openPendingSendsBox() {
    return Hive.openBox(_pendingSendsKey);
  }

  /// Opens box with users
  static Future<Box> _openUserBox() async {
    return Hive.openBox(_userKey);
  }

  /// Gets user by ID
  static Future<User?> getUserById(String userId) async {
    Box box = await _openUserBox();
    return box.get(userId);
  }

  // Check if user with ID exists
  static Future<bool> userExists(String userId) async {
    Box box = await _openUserBox();
    return box.containsKey(userId);
  }

  /// Add user to cache
  static Future<void> addUser(User user) async {
    Box box = await _openUserBox();
    await box.put(user.id, user);
  }

  /// Local-only chat list state (pinned, and later archived). Nothing here
  /// reaches the server: until F8 syncs it, it is this device's business.
  static const String _conversationsKey = 'conversations';

  static Future<Box> _openConversationsBox() async {
    return Hive.openBox(_conversationsKey);
  }

  static Map _metaOf(Box box, String userId) {
    final stored = box.get(userId);
    return stored is Map ? Map.from(stored) : <String, dynamic>{};
  }

  /// Whether [userId] is pinned to the top of the chat list.
  static Future<bool> isConversationPinned(String userId) async {
    final box = await _openConversationsBox();
    return _metaOf(box, userId)['pinned'] == true;
  }

  /// Pins or unpins a conversation. The entry is dropped once it is empty, so
  /// the box only holds chats that differ from the default.
  static Future<void> setConversationPinned(String userId, bool pinned) async {
    final box = await _openConversationsBox();
    final meta = _metaOf(box, userId);
    if (pinned) {
      meta['pinned'] = true;
    } else {
      meta.remove('pinned');
    }
    if (meta.isEmpty) {
      await box.delete(userId);
    } else {
      await box.put(userId, meta);
    }
  }

  /// Ids of the pinned conversations.
  static Future<Set<String>> getPinnedConversations() async {
    final box = await _openConversationsBox();
    return {
      for (final entry in box.toMap().entries)
        if (entry.value is Map && (entry.value as Map)['pinned'] == true)
          entry.key as String,
    };
  }

  /// Unread incoming messages per conversation, for the chat list badge.
  static Future<Map<String, int>> getUnreadCounts() async {
    final box = await _openPrivateMessagesBox();
    final counts = <String, int>{};
    for (final key in box.keys.whereType<String>()) {
      final userId = conversationOfKey(key);
      if (userId == null) {
        continue;
      }
      final value = box.get(key);
      if (value is PrivateMessage && !value.read) {
        counts[userId] = (counts[userId] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Oldest unread message of a conversation: the anchor of the "new messages"
  /// divider, taken before the chat marks everything read.
  static Future<DateTime?> firstUnreadSentAt(String userId) async {
    final box = await _openPrivateMessagesBox();
    DateTime? first;
    for (final key in _conversationKeys(box, userId)) {
      final value = box.get(key);
      if (value is! PrivateMessage || value.read) {
        continue;
      }
      if (first == null || value.sentAt.isBefore(first)) {
        first = value.sentAt;
      }
    }
    return first;
  }

  /// Get Map of all conversations with their last messages.
  ///
  /// Only the newest message of each conversation is deserialized, so the list
  /// does not pay for the whole history. Pinned conversations come first.
  static Future<Map<User, PrivateMessage>> getLatestPrivateMessages() async {
    Box box = await _openPrivateMessagesBox();
    await _migrateLegacyMessages(box);

    final newestKey = <String, String>{};
    final newestTimestamp = <String, int>{};
    for (final key in box.keys.whereType<String>()) {
      final userId = conversationOfKey(key);
      if (userId == null) {
        continue;
      }
      final timestamp = _timestampOfKey(key);
      if (timestamp > (newestTimestamp[userId] ?? -1)) {
        newestTimestamp[userId] = timestamp;
        newestKey[userId] = key;
      }
    }

    Map<User, PrivateMessage> conversations = {};
    for (final entry in newestKey.entries) {
      final message = box.get(entry.value);
      if (message is! PrivateMessage) {
        continue;
      }
      User? user = await getUserById(entry.key);
      conversations[user ?? User(entry.key, '', '', false)] = message;
    }
    // Pinned conversations first, then by last message date
    final pinnedIds = await getPinnedConversations();
    var sortedEntries = conversations.entries.toList()
      ..sort((a, b) {
        final aPinned = pinnedIds.contains(a.key.id);
        final bPinned = pinnedIds.contains(b.key.id);
        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }
        return b.value.receivedAt.compareTo(a.value.receivedAt);
      });
    return Map.fromEntries(sortedEntries);
  }

  /// Delete all private messages
  static Future<void> deleteAllPrivateMessagesWithUsers() async {
    Box messageBox = await _openPrivateMessagesBox();
    Box userBox = await _openUserBox();
    Box conceptBox = await _openMessageConceptBox();
    Box pendingBox = await _openPendingSendsBox();
    Box conversationsBox = await _openConversationsBox();
    await userBox.clear();
    await messageBox.clear();
    await conceptBox.clear();
    await pendingBox.clear();
    await conversationsBox.clear();
    // Remove every locally stored media file.
    await MediaUtils.clearMediaDir();
  }

  /// Opens box with message concepts
  static Future<Box> _openMessageConceptBox() async {
    return Hive.openBox(_messageConceptKey);
  }

  /// Sets message concept for user
  static Future<void> setMessageConcept(String userId, String message) async {
    Box box = await _openMessageConceptBox();
    await box.put(userId, message);
  }

  /// Return message concept for user
  static Future<String?> getMessageConcept(String userId) async {
    Box box = await _openMessageConceptBox();
    String? value = await box.get(userId);
    return value;
  }

  /// Delete message concept if it exists
  static Future<void> deleteMessageConcept(String userId) async {
    Box box = await _openMessageConceptBox();
    await box.delete(userId);
  }
}
