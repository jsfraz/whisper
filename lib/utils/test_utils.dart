import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
        Uint8List msgData = message as Uint8List;
        debugPrint('Received message: ${utf8.decode(msgData)}');
      });

      // Send messages to WS channel

      // Subscribe to topic
      var msg = {"action": "subscribe", "topic": "message"};
      // Send as binary data
      channel.sink.add(utf8.encode(jsonEncode(msg)));

      sleep(const Duration(seconds: 1));

      // Publish message to topic
      var msg2 = {
        "action": "publish",
        "topic": "message",
        "payload": {"message": "Hello from Whisper app!"}
      };
      // Send as binary data
      channel.sink.add(utf8.encode(jsonEncode(msg2)));

      /*
      // Close WS channel
      sleep(const Duration(seconds: 5));
      channel.sink.close();
      */
    } catch (e) {
      debugPrint('Error: $e');
    }
  }
}
