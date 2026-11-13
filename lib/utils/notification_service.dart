import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sprintf/sprintf.dart';
import '../utils/cache_utils.dart';
import '../models/user.dart';
import '../models/private_message.dart';
import 'singleton.dart';

// https://www.scaler.com/topics/flutter-local-notification/
class NotificationService {
  /// Set by HomePage while it is alive, so a tap on a single message
  /// notification can open the chat immediately instead of being queued.
  static void Function(String userId)? onChatSelected;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Init notification settings
  Future<void> init() async {
    // Local notifications are only set up for the platforms that have their
    // settings below. iOS/macOS need the Darwin settings tracked in the
    // "Android / iOS permissions" backlog item.
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.linux) {
      return;
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_stat_whisper');
    final LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(
      defaultActionName: 'whisper_message',
      defaultIcon: ThemeLinuxIcon('mail-unread'),
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
            android: initializationSettingsAndroid,
            linux: initializationSettingsLinux);

    await _flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTap);

    // Tapping a notification while the app was closed launches it through here
    // (Android only, the Linux implementation does not support it).
    if (defaultTargetPlatform == TargetPlatform.android) {
      final launchDetails = await _flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _setPendingChat(launchDetails!.notificationResponse?.payload);
      }
    }

    // FCM posts notifications into this channel, so it must exist before a push arrives
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(AndroidNotificationChannel(
          'whisper_firebase_messages',
          'Whisper',
          description: 'notificationChannelDesc'.tr(),
          importance: Importance.max,
          sound: const RawResourceAndroidNotificationSound('notification'),
        ));
  }

  /// Remember the chat a notification points at. The app may still be locked,
  /// so HomePage opens it once it is on screen (i.e. after unlocking).
  void _onNotificationTap(NotificationResponse response) =>
      _setPendingChat(response.payload);

  /// The payload of a single message notification is the sender id; grouped
  /// notifications carry none and just open HomePage.
  void _setPendingChat(String? payload) {
    final userId = payload ?? '';
    if (userId.isEmpty) {
      return;
    }
    final onChatSelected = NotificationService.onChatSelected;
    if (onChatSelected != null) {
      onChatSelected(userId);
      return;
    }
    Singleton().pendingChatUserId = userId;
  }

  /// Show notifications.
  Future<void> showMessagesNotification(List<PrivateMessage> messages) async {
    final Map<String, List<PrivateMessage>> groupedMessagesById = {};
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
        id: messages.last.notificationId,
        title: 'newMessagesTitle'.tr(),
        body: 'newMessagesBody'.tr(),
        notificationDetails: groupedPlatformChannelSpecifics,
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
              .map((message) => '${user.username}: ${message.preview}');
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
      enableVibration: true,
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
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
      // Message previews are long, don't let Android truncate them
      styleInformation: BigTextStyleInformation(message.preview),
    );
    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _flutterLocalNotificationsPlugin.show(
      id: message.notificationId,
      title: user.username,
      body: message.preview,
      notificationDetails: platformChannelSpecifics,
      payload: message.senderId.toString(),
    );
  }

  /// Remove notifications by ID
  Future<void> removeNotificationsById(List<int> ids) async {
    final activeNotifications =
        await _flutterLocalNotificationsPlugin.getActiveNotifications();
    for (var id in ids) {
      for (var notification in activeNotifications) {
        if (notification.id == id) {
          await _flutterLocalNotificationsPlugin.cancel(id: id);
        }
      }
    }
  }
}
