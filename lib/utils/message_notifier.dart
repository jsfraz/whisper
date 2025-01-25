import 'package:flutter/material.dart';

import '../models/private_message.dart';
import '../models/user.dart';
import 'cache_utils.dart';

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
  Future<List<PrivateMessage>> getMessages(int userId) {
    return CacheUtils.getPrivateMessages(userId);
  }

  /// Get latest private messages
  Future<Map<User,PrivateMessage>> getLatestPrivateMessages() async {
    var messages = CacheUtils.getLatestPrivateMessages();
    // TODO get missing users
    return messages;
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
}