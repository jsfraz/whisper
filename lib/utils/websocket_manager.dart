import 'dart:async';
import '../utils/utils.dart';

class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  Timer? _timer;

  // Private constructor for singleton pattern
  WebSocketManager._internal();

  // Factory constructor to return the same instance
  factory WebSocketManager() {
    return _instance;
  }

  // Start periodic connection check
  void startConnectionCheck() {
    _timer = Timer.periodic(Duration(seconds: 5), (timer) async {
      await Utils.wsConnect();
    });
  }

  // Stop the periodic connection check
  void stopConnectionCheck() {
    _timer?.cancel();
  }
}