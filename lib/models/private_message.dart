import 'package:hive/hive.dart';

import '../utils/singleton.dart';

part 'private_message.g.dart';

@HiveType(typeId: 3)
class PrivateMessage extends HiveObject {
  @HiveField(0)
  int senderId;
  @HiveField(1)
  String message;
  @HiveField(2)
  DateTime sentAt;
  @HiveField(3)
  DateTime receivedAt;
  @HiveField(4)
  bool read;

  PrivateMessage(this.senderId, this.message, this.sentAt, this.receivedAt, this.read);

  bool get isMe => senderId == Singleton().profile.user.id;

  int get notificationId => receivedAt.microsecondsSinceEpoch % 0x7FFFFFFF;
}