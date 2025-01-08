import 'package:bcrypt/bcrypt.dart';
import 'package:hive/hive.dart';
import '../models/profile.dart';
import 'singleton.dart';
import 'utils.dart';

class CacheUtils {
  static const _hashBoxKey = 'hash';
  static const _profileKey = 'profile';

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

  /// Delete encrypted cache and password hash from disk
  static Future<void> deleteCache() async {
    BoxCollection collection =
        await _openBoxCollectionWithoutKey({_profileKey});
    await collection.deleteFromDisk();
    Box box = await _openPasswordHashBox();
    await box.deleteFromDisk();
  }
}
