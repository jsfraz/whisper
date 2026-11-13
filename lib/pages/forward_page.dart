import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/chat_sender.dart';
import '../utils/media_utils.dart';
import '../utils/message_notifier.dart';
import '../widgets/user_list_item.dart';
import 'search_user_page.dart';

/// Picks the destination of a forwarded message: an existing conversation or a
/// user found by search. Sends the message and closes itself.
class ForwardPage extends StatefulWidget {
  const ForwardPage(this.message, {super.key});
  final PrivateMessage message;

  @override
  State<ForwardPage> createState() => _ForwardPageState();
}

class _ForwardPageState extends State<ForwardPage> {
  List<User> _chats = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    final chats = await MessageNotifier().getLatestPrivateMessages();
    if (mounted) {
      setState(() {
        _chats = chats.keys.toList();
      });
    }
  }

  Future<void> _forward(User to) async {
    if (_sending) {
      return;
    }
    setState(() {
      _sending = true;
    });
    try {
      final message = widget.message;
      bool sent;
      if (message.isMedia) {
        final path = message.localPath;
        final type = message.mediaType;
        if (path == null || type == null) {
          // Save/forward are hidden for attachments that are not on disk
          return;
        }
        final bytes = await MediaUtils.decryptAtRest(path);
        sent = await ChatSender.sendMedia(to, type, bytes,
            caption: message.message,
            width: message.width,
            height: message.height,
            durationMs: message.durationMs,
            fileName: message.fileName);
      } else {
        sent = await ChatSender.sendText(to, message.message);
      }
      if (!mounted) {
        return;
      }
      if (sent) {
        Fluttertoast.showToast(msg: 'forwarded'.tr());
        Navigator.pop(context);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('forwardTo'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'searchUserPage'.tr(),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SearchUserPage(onUserSelected: (user) {
                        // Close the search page, _forward closes this one
                        Navigator.pop(context);
                        _forward(user);
                      })));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _chats.isEmpty
            ? Center(child: Text('noChatsToForward'.tr()))
            : ListView.builder(
                itemCount: _chats.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: UserListItem(
                        _chats[index], () => _forward(_chats[index])),
                  );
                },
              ),
      ),
    );
  }
}
