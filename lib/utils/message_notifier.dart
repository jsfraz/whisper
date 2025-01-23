import 'package:flutter/material.dart';

import '../models/private_message.dart';
import 'cache_utils.dart';

class MessageNotifier extends ChangeNotifier {
  /// Singleton instance
  static final MessageNotifier _instance = MessageNotifier._internal();
  
  factory MessageNotifier() {
    return _instance;
  }
  
  MessageNotifier._internal();
  
  Future<void> addMessages(int userId, List<PrivateMessage> messages) async {
    await CacheUtils.addPrivateMessages(userId, messages);
    notifyListeners();
  }
  
  Future<List<PrivateMessage>> getMessages(int userId) {
    return CacheUtils.getPrivateMessages(userId);
  }
}