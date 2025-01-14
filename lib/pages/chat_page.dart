import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/user.dart';
import '../utils/color_utils.dart';
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: userColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.user.username.isNotEmpty
                      ? widget.user.username[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: ColorUtils.getReadableColor(userColor),
                    fontSize: 20,
                  ),
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
                          onPressed: null, // TODO send message
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
