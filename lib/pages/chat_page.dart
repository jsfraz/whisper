import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
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
import '../utils/crypto_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import '../widgets/chat_bubble.dart';
import 'package:basic_utils/basic_utils.dart' as bu;
import 'chat_info_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage(this.user, {super.key});
  final User user;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

// Transaprent AppBar: https://ckreymborg.medium.com/how-to-create-a-glassmorphism-frosted-glass-appbar-in-flutter-fb217ce1b4ca

class _ChatPageState extends State<ChatPage> {
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
    // Load messages from cache
    _loadMessages();
    // Load concept message
    getConceptMessage();
  }

  Future<void> getConceptMessage() async {
    String? conceptMsg = await CacheUtils.getMessageConcept(widget.user.id);
    if (conceptMsg != null) {
      _controllerMessage.text = conceptMsg;
    }
  }

  Future<void> _loadMessages() async {
    _messages = await MessageNotifier().getMessages(widget.user.id);
    MessageNotifier().notify();
    setState(() {});
  }

  /// Send message
  Future<void> _sendMessage() async {
    debugPrint(_controllerMessage.text.length.toString());
    if (_controllerMessage.text.isEmpty) {
      return;
    }
    setState(() {
      _isSending = true;
    });
    await Utils.wsConnect();
    // Send message
    if (Singleton().wsClient.isConnected) {
      // Encrypt message content
      Map<String, Uint8List> data;
      try {
        data = await CryptoUtils.encryptMessageData(
            utf8.encode(_controllerMessage.text),
            bu.CryptoUtils.rsaPublicKeyFromPem(widget.user.publicKey));
      } catch (e) {
        await Fluttertoast.showToast(
            msg: e.toString(), backgroundColor: Colors.red);
        setState(() {
          _isSending = false;
        });
        return;
      }
      DateTime sentAt;
      try {
        sentAt = Singleton().wsClient.sendMessage(WsMessage.privateMessage(
            NewPrivateMessage(widget.user.id, data['encryptedData']!,
                data['encryptedKey']!, data['nonce']!, data['mac']!)));
        // Save user to cache
        if (widget.user.publicKey != '' &&
            widget.user.username != '' &&
            !widget.user.isInBox) {
          CacheUtils.addUser(widget.user);
        }
        // Add message to cache
        await MessageNotifier().addMessages(widget.user.id, [
          PrivateMessage(Singleton().profile.user.id, _controllerMessage.text,
              sentAt, sentAt, true)
        ]);
        // Reset text
        _controllerMessage.text = '';
        // Delete concept
        await CacheUtils.deleteMessageConcept(widget.user.id);
      } catch (e) {
        await Fluttertoast.showToast(
            msg: e.toString(), backgroundColor: Colors.red);
      }
    } else {
      await Fluttertoast.showToast(
          msg: 'wsOffline', backgroundColor: Colors.red);
    }
    setState(() {
      _isSending = false;
    });
  }

  /// Get ListView with content
  ListView _getContent(List<PrivateMessage> messages) {
    _firstLoad = false;
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
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
                    backgroundColor: widget.user.avatarColor,
                    child: Text(
                      widget.user.username.isNotEmpty
                          ? widget.user.username[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 40,
                        color: widget.user.avatarTextColor,
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
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 50),
                      child: Text('legendaryChat'.tr(),
                          textAlign: TextAlign.center)),
                ],
              ),
            ),
          );
        }
        // Return chat bubble
        final previousMessage = index > 1 ? messages[index - 2] : null;
        final message = messages[index - 1];
        final nextMessage = index < messages.length ? messages[index] : null;
        return ChatBubble(previousMessage, message, nextMessage, widget.user);
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

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && _messages.isNotEmpty) {
          if (_controllerMessage.text.isNotEmpty) {
            await CacheUtils.setMessageConcept(
                widget.user.id, _controllerMessage.text);
          } else {
            await CacheUtils.deleteMessageConcept(widget.user.id);
          }
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: Size(
            double.infinity,
            56.0,
          ),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.2),
                leading: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: widget.user.avatarColor,
                      child: Text(
                        widget.user.username.isNotEmpty
                            ? widget.user.username[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 16,
                          color: widget.user.avatarTextColor,
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
                          duration: const Duration(milliseconds: 300),
                          reverseDuration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          type: PageTransitionType.rightToLeftJoined,
                          child: ChatInfoPage(widget.user.id),
                          childCurrent: widget));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Column(
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
                    // Set data
                    if (snapshot.hasData) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollController
                            .jumpTo(_scrollController.position.maxScrollExtent);
                      });
                      _messages = snapshot.data!;
                    }
                    // Return messages
                    return _getContent(_messages);
                  }),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: 5, left: 5),
                        // TODO certically expandable text field
                        child: TextField(
                          controller: _controllerMessage,
                          decoration: InputDecoration(
                            hintText: 'yourMessage'.tr(),
                            filled: true,
                            fillColor: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? Theme.of(context).colorScheme.surfaceBright
                                : Theme.of(context).colorScheme.surfaceDim,
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
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
