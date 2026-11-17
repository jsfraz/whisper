import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/chat_date.dart';

class ChatListItem extends StatefulWidget {
  const ChatListItem(this.user, this.lastMessage, this.onPressed,
      {this.unreadCount = 0, this.pinned = false, super.key});

  final User user;
  final PrivateMessage lastMessage;
  final Function() onPressed;

  /// Unread incoming messages of this conversation, for the badge.
  final int unreadCount;

  /// Whether the conversation is pinned to the top of the list.
  final bool pinned;

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  /// Rounded counter, capped the way every messenger does it.
  Widget _unreadBadge() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: scheme.onPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    /// Return message with or without "me: " prefix
    String getTitle() {
      String meText = widget.lastMessage.isMe ? '${'meText'.tr()}: ' : '';
      // Use preview text (caption, or a localized label for media).
      String preview = widget.lastMessage.preview;
      String msg =
          preview.length <= 14 ? preview : '${preview.substring(0, 14)}...';
      return meText + msg;
    }

    final bool unread = widget.unreadCount > 0 || !widget.lastMessage.read;

    return ListTile(
      onTap: widget.onPressed,
      tileColor: Colors.transparent,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: widget.user.avatarColor,
        child: Text(
          widget.user.username.isNotEmpty
              ? widget.user.username[0].toUpperCase()
              : '?',
          style: TextStyle(
            fontSize: 20,
            color: widget.user.avatarTextColor,
          ),
        ),
      ),
      title: Row(
        children: [
          if (widget.pinned)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.push_pin,
                  size: 14, color: Theme.of(context).colorScheme.primary),
            ),
          Expanded(
            child: Text(
              widget.user.username.isNotEmpty ? widget.user.username : '?',
              overflow: TextOverflow.ellipsis,
              style:
                  unread ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
        ],
      ),
      subtitle: Text(
        getTitle(),
        style: unread ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chatDateLabel(
              widget.lastMessage.receivedAt,
              todayLabel: 'todayText'.tr(),
              yesterdayLabel: 'yesterdayText'.tr(),
            ),
            style: unread
                ? TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),
          if (widget.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _unreadBadge(),
            ),
        ],
      ),
    );
  }
}
