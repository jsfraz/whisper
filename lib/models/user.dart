import 'package:hive/hive.dart';
import 'package:whisper_openapi_client/api.dart';

part 'user.g.dart';

@HiveType(typeId: 1)
class User extends HiveObject {
  User(this.id, this.username, this.mail, this.publicKey, this.admin);

  @HiveField(0)
  int id;
  @HiveField(1)
  String username;
  @HiveField(2)
  String mail;
  @HiveField(3)
  String publicKey;
  @HiveField(4)
  bool admin;

  /// Returns new User instance from OpenAPI user model.
  static User fromModel(ModelsUser user) {
    return User(user.id, user.username, user.mail, user.publicKey, user.admin);
  }
}
