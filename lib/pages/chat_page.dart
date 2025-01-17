import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:whisper_websocket_client_dart/models/new_private_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_message.dart';
import '../models/chat_message.dart';
import '../models/user.dart';
import '../utils/color_utils.dart';
import '../utils/singleton.dart';
import '../widgets/chat_message.dart';

class ChatPage extends StatefulWidget {
  const ChatPage(this.user, {super.key});
  final User user;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // Get color of user profile picture
  late final Color userColor;
  // Add controller for text input
  final TextEditingController _controllerMessage = TextEditingController();
  // Add list for messages
  final List<ChatMessage> _messages = [];
  // Buttons
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    userColor = ColorUtils.getColorFromUsername(widget.user.username);

    // Add test messages
    _messages.addAll([
      ChatMessage(
        text: "Hello, how are you??",
        isMe: false,
      ),
      ChatMessage(
        text: "Good, thanks! And you?",
        isMe: true,
      ),
      /*
      ChatMessage(
        text: "Hello, how are you??",
        isMe: false,
      ),
      ChatMessage(
        text: "Good, thanks! And you?",
        isMe: true,
      ),
      ChatMessage(
        text: "Hello, how are you??",
        isMe: false,
      ),
      ChatMessage(
        text: "Good, thanks! And you?",
        isMe: true,
      ),
      ChatMessage(
        text: "Hello, how are you??",
        isMe: false,
      ),
      ChatMessage(
        text: "Good, thanks! And you?",
        isMe: true,
      ),
      ChatMessage(
        text: "Hello, how are you??",
        isMe: false,
      ),
      ChatMessage(
        text: "Good, thanks! And you?",
        isMe: true,
      ),
      ChatMessage(
        text: "Hello, how are you??",
        isMe: false,
      ),
      ChatMessage(
        text: "Good, thanks! And you?",
        isMe: true,
      ),
      */
    ]);
  }

  /// Send message
  Future<void> _sendMessage() async {
    setState(() {
      _isSending = true;
    });
    // TODO Encrypt message content
    var encryptedMessage = utf8.encode(_controllerMessage.text);
    if (Singleton().wsClient.isConnected) {
      // Send message
      Singleton().wsClient.sendMessage(WsMessage.privateMessage(NewPrivateMessage.newPrivateMessage(widget.user.id, encryptedMessage)));
    } else {
      // TODO error or something
    }
    setState(() {
      _isSending = false;
    });
  }

  @override
  void dispose() {
    _controllerMessage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            CircleAvatar(
              radius: 22,
              backgroundColor: userColor,
              child: Text(
                widget.user.username.isNotEmpty
                    ? widget.user.username[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 20,
                  color: ColorUtils.getReadableColor(userColor),
                ),
              ),
            ),
          ],
        ),
        leadingWidth: 96, // Increase width to accommodate both icons
        // Title
        title: Text(widget.user.username),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages and avatar list
            Expanded(
              child: ListView.builder(
                reverse: false,
                itemCount: _messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Header with avatar (will appear at the top)
                    return Center(
                      child: Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 20),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: userColor,
                                child: Text(
                                  widget.user.username.isNotEmpty
                                      ? widget.user.username[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 40,
                                    color:
                                        ColorUtils.getReadableColor(userColor),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.user.username,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 30),
                              Text('legendaryChat'.tr()),
                            ],
                          )),
                    );
                  }
                  // Messages (adjust index to account for header)
                  final message = _messages[index - 1];
                  return ChatBubble(
                    message.text,
                    message.isMe,
                    message.isMe ? Colors.blue : Colors.grey[300]!,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controllerMessage,
                      decoration: InputDecoration(
                        hintText: 'yourMessage'.tr(),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceBright,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          onPressed: _isSending ? null : _sendMessage,
                          icon: const Icon(Icons.send),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
