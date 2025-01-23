import 'package:bcrypt/bcrypt.dart';
import 'package:hive/hive.dart';
import 'package:whisper/models/app_theme.dart';
import 'package:whisper/models/private_message.dart';
import '../models/profile.dart';
import 'singleton.dart';
import 'utils.dart';

class CacheUtils {
  static const _hashBoxKey = 'hash';
  static const _profileKey = 'profile';
  static const _themeKey = 'theme';
  static const _privateMessagesKey = 'privateMessages';

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
  static Future<void> addPrivateMessages(int userId, List<PrivateMessage> messages) async {
    Box box = await _openPrivateMessagesBox();
    List<PrivateMessage> chatMessages = await getPrivateMessages(userId);
    chatMessages.addAll(messages);
    await box.put(userId, chatMessages);
  }

  /// Get user messages
  static Future<List<PrivateMessage>> getPrivateMessages(int userId) async {
    Box box = await _openPrivateMessagesBox();
    List<dynamic>? messages = box.get(userId);
    return messages == null ? [] : messages.map((e) => e as PrivateMessage).toList();
  }
}
