/*
import 'package:hive/hive.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'user.dart';

part 'profile.g.dart';

@HiveType(typeId: 0)
class Profile extends HiveObject {
  Profile(this.basePath, this.accessToken, this.refreshToken, this.user,
      this.password);

  @HiveField(0)
  String basePath;
  @HiveField(1)
  String accessToken;
  @HiveField(2)
  String refreshToken;
  @HiveField(3)
  User user;
  @HiveField(4)
  String password;

  /// Checks if access token is expired
  bool isAccessTokenExpired() {
    return JwtDecoder.isExpired(accessToken);
  }

  /// Checks if refresh token is expired
  bool isRefreshTokenExpired() {
    return JwtDecoder.isExpired(refreshToken);
  }
}
*/