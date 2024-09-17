import 'package:hive/hive.dart';

import 'user.dart';

part 'profile.g.dart';

@HiveType(typeId: 0)
class Profile extends HiveObject {

  Profile(this.url ,this.user,);

  @HiveField(0)
  String url;
  @HiveField(1)
  User user;
}