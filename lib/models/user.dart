import 'dart:ui';

import 'package:hive/hive.dart';
import 'package:whisper_openapi_client_dart/api.dart';

import '../utils/color_utils.dart';

part 'user.g.dart';

@HiveType(typeId: 1)
class User extends HiveObject {
  User(this.id, this.username, this.publicKey, this.admin) {
    _avatarColor = ColorUtils.getAvatarColor(username);
    _avatarTextColor = ColorUtils.getReadableColor(_avatarColor);
  }

  @HiveField(0)
  int id;
  @HiveField(1)
  String username;
  @HiveField(2)
  String publicKey;
  @HiveField(3)
  bool admin;

  late Color _avatarColor;
  late Color _avatarTextColor;

  /// Returns new User instance from OpenAPI user model.
  static User fromModel(ModelsUser user) {
    return User(user.id, user.username, user.publicKey, user.admin);
  }

  Color get avatarColor {
    return _avatarColor;
  }

  Color get avatarTextColor {
    return _avatarTextColor;
  }
}
