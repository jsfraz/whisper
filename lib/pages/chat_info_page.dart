import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../utils/message_notifier.dart';
import '../utils/dialog_utils.dart';
import 'home_page.dart';

class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage(this.userId,{super.key});
  final int userId;

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('chatInfoPage'.tr()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // TODO Theme

            // TODO Media

            // Delete chat
            TextButton(
              onPressed: () async {
                await DialogUtils.yesNoDialog(context, 'deleteChatConfirm'.tr(),
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
    );
  }
}
