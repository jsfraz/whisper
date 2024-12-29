import 'package:hive/hive.dart';

import 'user.dart';

part 'profile.g.dart';

@HiveType(typeId: 0)
class Profile extends HiveObject {
  Profile(this.url, this.user, this.publicKey, this.privateKey,
      this.accessToken, this.refreshToken);

  @HiveField(0)
  String url;
  @HiveField(1)
  User user;
  @HiveField(2)
  String publicKey;
  @HiveField(3)
  String privateKey;
  @HiveField(4)
  String accessToken;
  @HiveField(5)
  String refreshToken;
}
