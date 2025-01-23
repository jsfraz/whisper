import 'package:flutter/material.dart';
import '../models/private_message.dart';

class ChatBubble extends StatelessWidget {
  final PrivateMessage message;

  const ChatBubble(this.message, {super.key});

  // TODO colors by theme
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: message.isMe ? Colors.blue : Colors.grey[300]!,    // TODO Color by theme
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            message.message,
            style: TextStyle(
              color: message.isMe ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
