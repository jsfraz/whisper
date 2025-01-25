import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/color_utils.dart';

class ChatListItem extends StatefulWidget {
  const ChatListItem(this.user, this.lastMessage, this.onPressed, {super.key});

  final User user;
  final PrivateMessage lastMessage;
  final Function() onPressed;

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  String formatDate() {
    final DateTime now = DateTime.now().toLocal();
    final DateTime messageDate = widget.lastMessage.receivedAt.toLocal();
    final int daysDifference = messageDate.difference(now).inDays;

    // Today
    if (messageDate.day == now.day &&
        messageDate.month == now.month &&
        messageDate.year == now.year) {
      return '${'todayText'.tr()} ${DateFormat.Hm().format(messageDate)}';
    }
    // Yesterday
    else if (daysDifference == -1) {
      return '${'yesterdayText'.tr()} ${DateFormat.Hm().format(messageDate)}';
    }
    // Last week
    else if (daysDifference >= -7) {
      return '${DateFormat.EEEE().format(messageDate)} ${DateFormat.Hm().format(messageDate)}';
    }
    // This year
    else if (messageDate.year == now.year) {
      return DateFormat.MMMMd().format(messageDate);
    }
    // Different year
    else {
      return DateFormat.yMMMMd().format(messageDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color userColor = ColorUtils.getColorFromUsername(widget.user.username);

    /// Return message with or without "me: " prefix
    String getTitle() {
      String meText = widget.lastMessage.isMe ? '${'meText'.tr()}: ' : '';
      String msg = widget.lastMessage.message.length <= 12
          ? widget.lastMessage.message
          : '${widget.lastMessage.message.substring(0, 12)}...';
      return meText + msg;
    }

    return ListTile(
      onTap: widget.onPressed,
      tileColor: Colors.transparent,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      leading: CircleAvatar(
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
      title: Text(widget.user.username.isNotEmpty ? widget.user.username : '?'),
      subtitle: Text(getTitle()),
      trailing: Text(
        formatDate(),
      ),
    );
  }
}
