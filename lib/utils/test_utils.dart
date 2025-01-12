import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class TestUtils {
  // https://docs.flutter.dev/cookbook/networking/web-sockets
  static void test(String url, String wsAccessToken) {
    try {
      // Convert http to ws or https to wss
      String wsUrl = url.contains('https')
          ? url.replaceFirst('https', 'wss')
          : url.replaceFirst('http', 'ws');
      wsUrl = '$wsUrl/ws';

      // Create WS channel
      final channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?wsAccessToken=$wsAccessToken'),
      );

      // Listen for messages from WS channel
      channel.stream.listen((message) {
        debugPrint('Received message: $message');
      });

      // Send message to WS channel
      var msg = {"action": "subscribe", "topic": "message"};
      channel.sink.add(jsonEncode(msg));
      sleep(const Duration(seconds: 1));
      var msg2 = {
        "action": "publish",
        "topic": "message",
        "payload": {"message": "Hello from Whisper app!"}
      };
      channel.sink.add(jsonEncode(msg2));

      /*
      // Close WS channel
      sleep(const Duration(seconds: 1));
      channel.sink.close();
      */
    } catch (e) {
      debugPrint('Error: $e');
    }
  }
}
