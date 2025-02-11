import 'package:flutter/material.dart';

import '../models/private_message.dart';
import '../models/user.dart';
import 'cache_utils.dart';
import 'singleton.dart';
import 'utils.dart';

class MessageNotifier extends ChangeNotifier {
  /// Singleton instance
  static final MessageNotifier _instance = MessageNotifier._internal();

  factory MessageNotifier() {
    return _instance;
  }

  MessageNotifier._internal();

  /// Add messages to cache
  Future<void> addMessages(int userId, List<PrivateMessage> messages) async {
    await CacheUtils.addPrivateMessages(userId, messages);
    notifyListeners();
  }

  /// Get all messages by user ID
  Future<List<PrivateMessage>> getMessages(int userId) async {
    return await CacheUtils.getPrivateMessages(userId, markAsRead: true);
  }

  /// Get latest private messages
  Future<Map<User, PrivateMessage>> getLatestPrivateMessages() async {
    var messages = await CacheUtils.getLatestPrivateMessages();
    Map<User, PrivateMessage> newMessages = {};
    // Get missing users
    for (var e in messages.entries) {
      // User does not exists in cache
      if (!e.key.isInBox) {
        var user =
            await Utils.callApi(() => Singleton().userApi.getUserById(e.key.id));
        if (user != null) {
          // Save user to cache
          await CacheUtils.addUser(User.fromModel(user));
          // Get the message for the old user
          var message = messages[e.key];
          // Add new entry with updated user
          newMessages[User.fromModel(user)] = message!;
        }
      } else {
        newMessages[e.key] = e.value;
      }
    }
    // Sort conversations by last message date
    var sortedEntries = newMessages.entries.toList()
      ..sort((a, b) => b.value.receivedAt.compareTo(a.value.receivedAt));
    return Map.fromEntries(sortedEntries);
  }

  /// Delete all chats
  Future<void> deleteAllChats() async {
    await CacheUtils.deleteAllPrivateMessagesWithUsers();
    notifyListeners();
  }

  /// Delete chat by user ID
  Future<void> deleteChat(int userId) async {
    await CacheUtils.deletePrivateMessagesWithUser(userId);
    notifyListeners();
  }

  void notify() {
    notifyListeners();
  }
}
