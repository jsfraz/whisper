import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../utils/cache_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/dialog_utils.dart';
import '../utils/singleton.dart';
import '../utils/theme_utils.dart';
import 'home_page.dart';

class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage(this.userId, {super.key});
  final int userId;

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  Color? _chatThemeColor;

  @override
  void initState() {
    super.initState();
    _loadChatTheme();
  }

  Future<void> _loadChatTheme() async {
    Color? color = await CacheUtils.getChatTheme(widget.userId);
    if (mounted) {
      setState(() {
        _chatThemeColor = color;
      });
    }
  }

  /// Pick a per-chat theme color
  Future<void> _pickChatTheme() async {
    Color? color = await showDialog<Color>(
        context: context,
        builder: (context) => DialogUtils.colorPickerDialog(
            context, _chatThemeColor ?? Singleton().appTheme.color));
    if (color == null || !mounted) {
      return;
    }
    await CacheUtils.setChatTheme(widget.userId, color);
    await _loadChatTheme();
  }

  /// Drop the per-chat theme and fall back to the global one
  Future<void> _clearChatTheme() async {
    await CacheUtils.clearChatTheme(widget.userId);
    await _loadChatTheme();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeUtils.chatTheme(context, _chatThemeColor),
      child: Scaffold(
        appBar: AppBar(
          title: Text('chatInfoPage'.tr()),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Chat theme
              TextButton(
                onPressed: _pickChatTheme,
                child: Row(
                  children: [
                    Icon(
                      Icons.palette,
                      size: 24,
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Text(
                        'chatTheme'.tr(),
                      ),
                    ),
                    if (_chatThemeColor != null)
                      Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _chatThemeColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 24,
                    ),
                  ],
                ),
              ),
              // Drop the override
              if (_chatThemeColor != null)
                TextButton(
                  onPressed: _clearChatTheme,
                  child: Row(
                    children: [
                      Icon(
                        Icons.restart_alt,
                        size: 24,
                      ),
                      Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Text(
                          'useGlobalTheme'.tr(),
                        ),
                      ),
                      SizedBox(
                        width: 24,
                      ),
                    ],
                  ),
                ),

              // TODO Media

              // Delete chat
              TextButton(
                onPressed: () async {
                  await DialogUtils.yesNoDialog(
                      context,
                      'deleteChatConfirm'.tr(),
                      'deleteChatConfirmText'.tr(), () async {
                    MessageNotifier().deleteChat(widget.userId);
                    // Redirect to home page and clear navigation stack
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const HomePage()),
                      (route) => false,
                    );
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever,
                      size: 24,
                      color: Colors.red,
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Text(
                        'deleteChat'.tr(),
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    SizedBox(
                      width: 24,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
