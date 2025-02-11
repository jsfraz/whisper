import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sprintf/sprintf.dart';
import 'package:whisper/utils/cache_utils.dart';
import '../models/user.dart';
import '../models/private_message.dart';

// https://www.scaler.com/topics/flutter-local-notification/
class NotificationService {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Init notification settings
  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_launcher_foreground');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  /// Show notifications.
  Future<void> showMessagesNotification(List<PrivateMessage> messages) async {
    final Map<int, List<PrivateMessage>> groupedMessagesById = {};
    for (var message in messages) {
      if (!groupedMessagesById.containsKey(message.senderId)) {
        groupedMessagesById[message.senderId] = [];
      }
      groupedMessagesById[message.senderId]!.add(message);
    }
    final Map<User, List<PrivateMessage>> groupedMessagesByUser = {};
    for (var entry in groupedMessagesById.entries) {
      User? user = await CacheUtils.getUserById(entry.key);
      List<dynamic> messages = entry.value;
      groupedMessagesByUser[user ?? User(entry.key, '', '', false)] =
          messages as List<PrivateMessage>;
    }

    if (messages.length == 1) {
      showMessageNotification(messages.first);
    }

    if (messages.length > 1) {
      final groupedPlatformChannelSpecifics = await groupedNotificationDetails(
          groupedMessagesByUser, messages.length);
      await _flutterLocalNotificationsPlugin.show(
        0,
        'newMessagesTitle'.tr(),
        'newMessagesBody'.tr(),
        groupedPlatformChannelSpecifics,
      );
    }
  }

  /// Show group notification for more messages
  Future<NotificationDetails> groupedNotificationDetails(
      Map<User, List<PrivateMessage>> messages, int totalMessageCount) async {
    final List<String> lines = messages.entries.expand((entry) {
      final user = entry.key;
      final userMessages = entry.value;
      // Sort messages
      userMessages.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      return userMessages
          .map((message) => '${user.username}: ${message.message}');
    }).toList();

    InboxStyleInformation inboxStyleInformation = InboxStyleInformation(lines,
        contentTitle: sprintf('xMessagesFromYChats'.tr(),
            [totalMessageCount, messages.keys.length]));
    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'whisperLocal',
      'whisperLocal',
      groupKey: 'cz.josefraz.flutter_push_notifications',
      channelDescription: 'notificationChannelDesc'.tr(),
      setAsGroupSummary: true,
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'tickerLocalNotification'.tr(),
      enableVibration: false,
      styleInformation: inboxStyleInformation,
    );

    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    return platformChannelSpecifics;
  }

  /// Show notification for one message
  Future<void> showMessageNotification(PrivateMessage message) async {
    var user = await CacheUtils.getUserById(message.senderId) ??
        User(message.senderId, '', '', false);

    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'whisperLocal',
      'whisperLocal',
      groupKey: 'cz.josefraz.flutter_push_notifications',
      channelDescription: 'notificationChannelDesc'.tr(),
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'tickerLocalNotification'.tr(),
      enableVibration: false,
    );
    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _flutterLocalNotificationsPlugin.show(
        0, user.username, message.message, platformChannelSpecifics);
  }
}
