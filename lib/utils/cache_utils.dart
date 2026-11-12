import 'dart:io';
import 'dart:ui' show Color;

import 'package:bcrypt/bcrypt.dart';
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
  static const _biometry = 'biometry';
  static const _chatThemeKeyPrefix = 'chatTheme:';

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
    Box privateMessagesBox = await _openPrivateMessagesBox();
    await privateMessagesBox.deleteFromDisk();
    Box userBox = await _openUserBox();
    userBox.deleteFromDisk();
    Box messageConceptBox = await _openMessageConceptBox();
    messageConceptBox.deleteFromDisk();
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
    final List<int> newKey = await CryptoUtils.pbkdf2(newPassword);
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
      await setPasswordHash(newPassword);
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
    return true;
  }

  /// Returns per-chat theme color, null means the global theme is used
  static Future<Color?> getChatTheme(int userId) async {
    Box box = await _openThemeBox();
    String? hex = box.get('$_chatThemeKeyPrefix$userId');
    return hex == null ? null : ColorUtils.colorFromHex(hex);
  }

  /// Sets per-chat theme color
  static Future<void> setChatTheme(int userId, Color color) async {
    Box box = await _openThemeBox();
    await box.put('$_chatThemeKeyPrefix$userId', ColorUtils.colorToHex(color));
  }

  /// Clears per-chat theme color, the chat falls back to the global theme
  static Future<void> clearChatTheme(int userId) async {
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

  /// Opens box with private messages
  static Future<Box> _openPrivateMessagesBox() async {
    return Hive.openBox(_privateMessagesKey);
  }

  /// Add user message to cache
  static Future<void> addPrivateMessages(
      int userId, List<PrivateMessage> messages) async {
    Box box = await _openPrivateMessagesBox();
    List<PrivateMessage> chatMessages = await getPrivateMessages(userId);
    chatMessages.addAll(messages);
    await box.put(userId, chatMessages);
  }

  /// Get user messages and mark them as read
  static Future<List<PrivateMessage>> getPrivateMessages(int userId,
      {bool markAsRead = false}) async {
    Box box = await _openPrivateMessagesBox();
    List<dynamic>? messages = box.get(userId);
    // Mark as read
    if (markAsRead && messages != null) {
      for (PrivateMessage msg in messages) {
        msg.read = true;
      }
      await box.put(userId, messages);
    }
    return messages == null
        ? []
        : messages.map((e) => e as PrivateMessage).toList();
  }

  /// Delete user messages
  static Future<void> deletePrivateMessagesWithUser(int userId) async {
    Box messageBox = await _openPrivateMessagesBox();
    // Delete on-disk media files for this conversation first.
    await _deleteMediaFilesForUser(userId);
    await messageBox.delete(userId);
    Box userBox = await _openUserBox();
    await userBox.delete(userId);
    await deleteMessageConcept(userId);
  }

  /// Delete the encrypted-at-rest media files of all messages with [userId].
  static Future<void> _deleteMediaFilesForUser(int userId) async {
    final messages = await getPrivateMessages(userId);
    for (final msg in messages) {
      if (msg.localPath != null) {
        await MediaUtils.deleteLocalFile(msg.localPath);
      }
    }
  }

  /// Update the local media state of a stored message (download progress).
  static Future<void> updatePrivateMessageMedia(int userId, String mediaId,
      {String? localPath, int? downloadStatus}) async {
    Box box = await _openPrivateMessagesBox();
    List<dynamic>? messages = box.get(userId);
    if (messages == null) {
      return;
    }
    bool changed = false;
    for (final dynamic m in messages) {
      final msg = m as PrivateMessage;
      if (msg.mediaId == mediaId) {
        if (localPath != null) {
          msg.localPath = localPath;
        }
        if (downloadStatus != null) {
          msg.downloadStatus = downloadStatus;
        }
        changed = true;
      }
    }
    if (changed) {
      await box.put(userId, messages);
    }
  }

  /// Opens box with users
  static Future<Box> _openUserBox() async {
    return Hive.openBox(_userKey);
  }

  /// Gets user by ID
  static Future<User?> getUserById(int userId) async {
    Box box = await _openUserBox();
    return box.get(userId);
  }

  // Check if user with ID exists
  static Future<bool> userExists(int userId) async {
    Box box = await _openUserBox();
    return box.containsKey(userId);
  }

  /// Add user to cache
  static Future<void> addUser(User user) async {
    Box box = await _openUserBox();
    await box.put(user.id, user);
  }

  /// Get Map of all conversations with their last messages
  static Future<Map<User, PrivateMessage>> getLatestPrivateMessages() async {
    Box box = await _openPrivateMessagesBox();
    Map<User, PrivateMessage> conversations = {};
    for (var entry in box.toMap().entries) {
      User? user = await getUserById(entry.key as int);
      List<dynamic> messages = entry.value;
      conversations[user ?? User(entry.key as int, '', '', false)] =
          messages.last as PrivateMessage;
    }
    // Sort conversations by last message date
    var sortedEntries = conversations.entries.toList()
      ..sort((a, b) => b.value.receivedAt.compareTo(a.value.receivedAt));
    return Map.fromEntries(sortedEntries);
  }

  /// Delete all private messages
  static Future<void> deleteAllPrivateMessagesWithUsers() async {
    Box messageBox = await _openPrivateMessagesBox();
    Box userBox = await _openUserBox();
    Box conceptBox = await _openMessageConceptBox();
    await userBox.clear();
    await messageBox.clear();
    await conceptBox.clear();
    // Remove every locally stored media file.
    await MediaUtils.clearMediaDir();
  }

  /// Opens box with message concepts
  static Future<Box> _openMessageConceptBox() async {
    return Hive.openBox(_messageConceptKey);
  }

  /// Sets message concept for user
  static Future<void> setMessageConcept(int userId, String message) async {
    Box box = await _openMessageConceptBox();
    await box.put(userId, message);
  }

  /// Return message concept for user
  static Future<String?> getMessageConcept(int userId) async {
    Box box = await _openMessageConceptBox();
    String? value = await box.get(userId);
    return value;
  }

  /// Delete message concept if it exists
  static Future<void> deleteMessageConcept(int userId) async {
    Box box = await _openMessageConceptBox();
    await box.delete(userId);
  }
}
