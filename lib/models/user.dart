/*
import 'package:hive/hive.dart';
import 'package:whisper_openapi_client/api.dart';

part 'user.g.dart';

@HiveType(typeId: 1)
class User extends HiveObject {
  User(this.id, this.username, this.hasImage, this.publicKey);

  @HiveField(0)
  int id;
  @HiveField(1)
  String username;
  @HiveField(2)
  bool hasImage;
  @HiveField(3)
  String publicKey;

  /// Returns new User instance from OpenAPI user model
  static User fromModelsUser(ModelsUser user) {
    return User(user.id, user.username, user.hasImage, user.publicKey);
  }
}
*/