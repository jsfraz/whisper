import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:page_transition/page_transition.dart';
import 'package:provider/provider.dart';
import 'package:whisper_websocket_client_dart/models/new_private_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_message.dart';
import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/cache_utils.dart';
import '../utils/color_utils.dart';
import '../utils/crypto_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/singleton.dart';
import '../widgets/chat_bubble.dart';
import 'package:basic_utils/basic_utils.dart' as bu;

import 'chat_info_page.dart';

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
  List<PrivateMessage> _messages = [];
  // Buttons
  bool _isSending = false;
  // ScrollController for content
  final ScrollController _scrollController = ScrollController();
  // Indicates whether messages are being load for the first time
  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    userColor = ColorUtils.getColorFromUsername(widget.user.username);
    // Load messages from cache
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    _messages = await CacheUtils.getPrivateMessages(widget.user.id);
    setState(() {});
  }

  /// Send message
  Future<void> _sendMessage() async {
    setState(() {
      _isSending = true;
    });
    // Encrypt message content
    Uint8List encryptedMessage;
    try {
      encryptedMessage = await CryptoUtils.rsaEncrypt(
          utf8.encode(_controllerMessage.text),
          bu.CryptoUtils.rsaPublicKeyFromPem(widget.user.publicKey));
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
      setState(() {
        _isSending = false;
      });
      return;
    }
    // Send message
    if (Singleton().wsClient.isConnected) {
      DateTime sentAt;
      try {
        sentAt = Singleton().wsClient.sendMessage(WsMessage.privateMessage(
            NewPrivateMessage(widget.user.id, encryptedMessage)));
        // Save user to cache
        if (widget.user.publicKey != '' &&
            widget.user.username != '' &&
            !widget.user.isInBox) {
          CacheUtils.addUser(widget.user);
        }
        // Add message to cache
        await MessageNotifier().addMessages(widget.user.id, [
          PrivateMessage(Singleton().profile.user.id, _controllerMessage.text,
              sentAt, sentAt)
        ]);
        // Reset text
        _controllerMessage.text = '';
      } catch (e) {
        // TODO error or something
      }
    } else {
      // TODO error or something
    }
    setState(() {
      _isSending = false;
    });
  }

  /// Get ListView with content
  ListView _getContent(List<PrivateMessage> messages) {
    _firstLoad = false;
    return ListView.builder(
      controller: _scrollController,
      reverse: false,
      itemCount: messages.length + 1,
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
                        color: ColorUtils.getReadableColor(userColor),
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
              ),
            ),
          );
        }
        // Messages (adjust index to account for header)
        final message = messages[index - 1];
        return ChatBubble(message);
      },
    );
  }

  @override
  void dispose() {
    _controllerMessage.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<MessageNotifier>();

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
              radius: 18,
              backgroundColor: userColor,
              child: Text(
                widget.user.username.isNotEmpty
                    ? widget.user.username[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 16,
                  color: ColorUtils.getReadableColor(userColor),
                ),
              ),
            ),
          ],
        ),
        leadingWidth: 96, // Increase width to accommodate both icons
        // Title
        title: Text(widget.user.username),
        // Action buttons
        actions: [
          IconButton(
            icon: const Icon(Icons.info),
            tooltip: 'infoButton'.tr(),
            onPressed: () {
              // Push info page
              Navigator.of(context).push(PageTransition(
                  type: PageTransitionType.rightToLeftJoined,
                  child: ChatInfoPage(widget.user.id),
                  childCurrent: widget));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages and avatar list
            Expanded(
              child: FutureBuilder<List<PrivateMessage>>(
                  future: notifier.getMessages(widget.user.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _firstLoad) {
                      return Center(
                        child: Transform.scale(
                          scale: 1.5,
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    // Return when data is present
                    if (snapshot.hasData) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollController
                            .jumpTo(_scrollController.position.maxScrollExtent);
                      });
                      return _getContent(snapshot.data!);
                    }
                    // Return with messages loaded on init
                    return _getContent(_messages);
                  }),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    // TODO color by theme
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
