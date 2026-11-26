import 'dart:async';
import 'dart:math';

import '../utils/utils.dart';

/// Keeps the WebSocket connected with exponential backoff.
///
/// A fixed short interval cost a token request every few seconds, on battery and
/// on the server, even when the device was offline for hours.
class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  Timer? _timer;
  bool _running = false;
  int _attempt = 0;

  /// First retry delay; doubles up to [maxDelay].
  static const Duration _initialDelay = Duration(seconds: 2);
  static const Duration maxDelay = Duration(seconds: 60);

  /// Private constructor for singleton pattern
  WebSocketManager._internal();

  /// Factory constructor to return the same instance
  factory WebSocketManager() {
    return _instance;
  }

  /// Delay before the next connection attempt. Exposed for tests.
  static Duration delayForAttempt(int attempt) {
    // Clamp the exponent before shifting: 2^attempt overflows an int long
    // before the delay is capped.
    final exponent = attempt < 0 ? 0 : min(attempt, 16);
    final seconds = _initialDelay.inSeconds * pow(2, exponent).toInt();
    return Duration(seconds: min(seconds, maxDelay.inSeconds));
  }

  /// Start the reconnect loop.
  void startConnectionCheck() {
    _timer?.cancel();
    _running = true;
    _attempt = 0;
    _scheduleNext();
  }

  /// Stop the reconnect loop.
  void stopConnectionCheck() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleNext() {
    if (!_running) {
      return;
    }
    _timer = Timer(delayForAttempt(_attempt), () async {
      await Utils.wsConnect();
      // A successful connection restarts the schedule from the short delay.
      _attempt = Utils.isOnline ? 0 : _attempt + 1;
      _scheduleNext();
    });
  }
}
