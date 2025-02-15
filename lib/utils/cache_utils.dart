import 'package:bcrypt/bcrypt.dart';
import 'package:hive/hive.dart';
import '../models/app_theme.dart';
import '../models/private_message.dart';
import '../models/profile.dart';
import '../models/user.dart';
import 'singleton.dart';
import 'utils.dart';

class CacheUtils {
  static const _hashBoxKey = 'hash';
  static const _profileKey = 'profile';
  static const _themeKey = 'theme';
  static const _privateMessagesKey = 'privateMessages';
  static const _userKey = 'user';
  static const _messageConceptKey = 'messageConcept';

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
    await messageBox.delete(userId);
    Box userBox = await _openUserBox();
    await userBox.delete(userId);
    await deleteMessageConcept(userId);
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
