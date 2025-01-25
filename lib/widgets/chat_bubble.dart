import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/private_message.dart';
import '../utils/color_utils.dart';

class ChatBubble extends StatelessWidget {
  final PrivateMessage? previousMessage;
  final PrivateMessage message;
  final PrivateMessage? nextMessage;
  final User user;

  const ChatBubble(
      this.previousMessage, this.message, this.nextMessage, this.user,
      {super.key});

  // TODO colors by theme
  @override
  Widget build(BuildContext context) {
    Color userColor = ColorUtils.getColorFromUsername(user.username);

    bool showAvatar() {
      if (message.isMe) return false;
      // Show avatar if next message is null (last message)
      if (nextMessage == null) return true;
      // Show avatar if next message is from different user
      return nextMessage!.senderId != message.senderId;
    }

    bool isFromSameUser() {
      if (previousMessage == null) return false;
      return previousMessage!.senderId == message.senderId;
    }

    bool shouldShowTime() {
      if (previousMessage == null) return true;

      final previousTime = previousMessage!.isMe
          ? previousMessage!.sentAt
          : previousMessage!.receivedAt;

      final currentTime = message.isMe ? message.sentAt : message.receivedAt;

      final difference = currentTime.difference(previousTime).inMinutes;
      return difference >= 10;
    }

    String formatDate(DateTime date) {
      final DateTime now = DateTime.now().toLocal();
      final DateTime messageDate = date.toLocal();
      final int daysDifference = messageDate.difference(now).inDays;

      // Today
      if (messageDate.day == now.day &&
          messageDate.month == now.month &&
          messageDate.year == now.year) {
        return DateFormat.Hm().format(messageDate);
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
        return '${DateFormat.MMMMd().format(messageDate)} ${DateFormat.Hm().format(messageDate)}';
      }
      // Different year
      else {
        return '${DateFormat.yMMMMd().format(messageDate)} ${DateFormat.Hm().format(messageDate)}';
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        left: message.isMe ? 96 : 16,
        right: message.isMe ? 16 : 96,
        top: isFromSameUser() ? 4 : 16,
      ),
      child: Column(
        crossAxisAlignment:
            message.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (shouldShowTime())
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Center(
                child: Text(
                  formatDate(
                      message.isMe ? message.sentAt : message.receivedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
          Align(
            alignment:
                message.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisAlignment: message.isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!message.isMe)
                  SizedBox(
                    width: 40, // 32 (avatar) + 8 (padding)
                    child: showAvatar()
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: userColor,
                              child: Text(
                                user.username.isNotEmpty
                                    ? user.username[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: ColorUtils.getReadableColor(userColor),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: message.isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      /*
                      // Show nick
                      if (!message.isMe)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 4),
                          child: Text(
                            user.username,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      */
                      Container(
                        decoration: BoxDecoration(
                          color: message.isMe
                              ? Colors.blue
                              : Colors.grey[300]!, // TODO Color by theme
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Text(
                          message.message,
                          style: TextStyle(
                            color: message.isMe ? Colors.white : Colors.black,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
