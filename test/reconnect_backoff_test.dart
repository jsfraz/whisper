import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/websocket_manager.dart';

void main() {
  test('reconnects back off instead of polling every few seconds', () {
    expect(WebSocketManager.delayForAttempt(0), const Duration(seconds: 2));
    expect(WebSocketManager.delayForAttempt(1), const Duration(seconds: 4));
    expect(WebSocketManager.delayForAttempt(2), const Duration(seconds: 8));
    expect(WebSocketManager.delayForAttempt(3), const Duration(seconds: 16));
  });

  test('the delay is capped so a long offline period stays cheap', () {
    expect(WebSocketManager.delayForAttempt(10), WebSocketManager.maxDelay);
    expect(WebSocketManager.delayForAttempt(100), WebSocketManager.maxDelay);
  });
}
