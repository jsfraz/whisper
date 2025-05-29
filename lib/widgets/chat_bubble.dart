import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/private_message.dart';

// TODO show options on bottom on holding the widget (like in Messenger - copy etc)
class ChatBubble extends StatefulWidget {
  final PrivateMessage? previousMessage;
  final PrivateMessage message;
  final PrivateMessage? nextMessage;
  final User user;

  const ChatBubble(
      this.previousMessage, this.message, this.nextMessage, this.user,
      {super.key});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _showTooltip = false;

  @override
  void initState() {
    super.initState();
    /*
    if (!widget.message.read) {
      widget.message.read = true;
      widget.message.save();
    }
    */
  }

  @override
  Widget build(BuildContext context) {
    bool showAvatar() {
      if (widget.message.isMe) return false;
      // Show avatar if next message is null (last message)
      if (widget.nextMessage == null) return true;
      // Show avatar if next message is from different user
      return widget.nextMessage!.senderId != widget.message.senderId;
    }

    bool isFromSameUser() {
      if (widget.previousMessage == null) return false;
      return widget.previousMessage!.senderId == widget.message.senderId;
    }

    bool shouldShowTime() {
      if (widget.previousMessage == null) return true;

      final previousTime = widget.previousMessage!.isMe
          ? widget.previousMessage!.sentAt
          : widget.previousMessage!.receivedAt;

      final currentTime = widget.message.isMe ? widget.message.sentAt : widget.message.receivedAt;

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

    Color bubbleBackground() {
      var brightness = Theme.of(context).brightness;
      if (widget.message.isMe) {
        if (brightness == Brightness.dark) {
          return Theme.of(context).colorScheme.secondary;
        }
        return Theme.of(context).colorScheme.primary;
      } else {
        if (brightness == Brightness.dark) {
          return Theme.of(context).colorScheme.onSecondary;
        }
        return Theme.of(context).colorScheme.surfaceDim;
      }
    }

    Color bubbleTextColor() {
      final backgroundColor = bubbleBackground();
      double luminance = backgroundColor.computeLuminance();
      return luminance > 0.5 ? Colors.black : Colors.white;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: widget.message.isMe ? 96 : 16,
        right: widget.message.isMe ? 16 : 96,
        top: isFromSameUser() ? 4 : 16,
      ),
      child: Column(
        crossAxisAlignment:
            widget.message.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  if (_showTooltip && !shouldShowTime())
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Center(
                        child: Text(
                          formatDate(
                              widget.message.isMe ? widget.message.sentAt : widget.message.receivedAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  if (shouldShowTime())
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Center(
                        child: Text(
                          formatDate(
                              widget.message.isMe ? widget.message.sentAt : widget.message.receivedAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _showTooltip = !_showTooltip;
              });
            },
            child: Align(
              alignment:
                  widget.message.isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: widget.message.isMe
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!widget.message.isMe)
                    SizedBox(
                      width: 40, // 32 (avatar) + 8 (padding)
                      child: showAvatar()
                          ? Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: widget.user.avatarColor,
                                child: Text(
                                  widget.user.username.isNotEmpty
                                      ? widget.user.username[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: widget.user.avatarTextColor,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: widget.message.isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        /*
                        // Show nick
                        if (!widget.message.isMe)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 4),
                            child: Text(
                              widget.user.username,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        */
                        Container(
                          decoration: BoxDecoration(
                            color: bubbleBackground(),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Text(
                            widget.message.message,
                            style: TextStyle(
                              color: bubbleTextColor(),
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
          ),
        ],
      ),
    );
  }
}
