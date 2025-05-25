import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sprintf/sprintf.dart';
import '../utils/cache_utils.dart';
import '../models/user.dart';
import '../models/private_message.dart';

// https://www.scaler.com/topics/flutter-local-notification/
class NotificationService {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Init notification settings
  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');

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

    // One message
    if (messages.length == 1) {
      showMessageNotification(messages.first);
    }
    // More messages
    if (messages.length > 1) {
      final lines = getGroupedNotificationLines(groupedMessagesByUser);
      final groupedPlatformChannelSpecifics = await groupedNotificationDetails(
          lines, groupedMessagesByUser.keys.length, messages.length);
      await _flutterLocalNotificationsPlugin.show(
        messages.last.notificationId,
        'newMessagesTitle'.tr(),
        'newMessagesBody'.tr(),
        groupedPlatformChannelSpecifics,
      );
    }
  }

  /// Get lines for grouped notification
  List<String> getGroupedNotificationLines(
      Map<User, List<PrivateMessage>> messages) {
    return messages.entries
        .expand((entry) {
          final user = entry.key;
          final userMessages = entry.value;
          // Sort messages
          userMessages.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
          return userMessages
              .map((message) => '${user.username}: ${message.message}');
        })
        .toList()
        .reversed
        .toList();
  }

  /// Show group notification for more messages
  Future<NotificationDetails> groupedNotificationDetails(
      List<String> lines, int chatCount, int totalMessageCount) async {
    InboxStyleInformation inboxStyleInformation = InboxStyleInformation(lines,
        contentTitle: sprintf(
            'xMessagesFromYChats'.tr(), [totalMessageCount, chatCount]));
    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'whisperLocalNotificationMultipleMessages',
      'whisperLocalNotificationMultipleMessages'.tr(),
      groupKey: 'cz.josefraz.flutter_push_notifications_multiple_messages',
      channelDescription: 'notificationChannelDesc'.tr(),
      setAsGroupSummary: true,
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'tickerLocalNotification'.tr(),
      enableVibration: false,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
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
      'whisperLocalNotificationSingleMessage',
      'whisperLocalNotificationSingleMessage'.tr(),
      groupKey: 'cz.josefraz.flutter_push_notifications_single_message',
      channelDescription: 'notificationChannelDesc'.tr(),
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'tickerLocalNotification'.tr(),
      enableVibration: false,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
    );
    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _flutterLocalNotificationsPlugin.show(
      message.notificationId,
      user.username,
      message.message,
      platformChannelSpecifics,
    );
  }

  /// Remove notifications by ID
  Future<void> removeNotificationsById(List<int> ids) async {
    final activeNotifications =
        await _flutterLocalNotificationsPlugin.getActiveNotifications();
    for (var id in ids) {
      for (var notification in activeNotifications) {
        if (notification.id == id) {
          await _flutterLocalNotificationsPlugin.cancel(id);
        }
      }
    }
  }
}
