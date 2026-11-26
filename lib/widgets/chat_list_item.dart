import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/chat_date.dart';
import '../utils/presence.dart';

class ChatListItem extends StatefulWidget {
  const ChatListItem(this.user, this.lastMessage, this.onPressed,
      {this.unreadCount = 0, this.pinned = false, this.peerReadAt, super.key});

  final User user;
  final PrivateMessage lastMessage;
  final Function() onPressed;

  /// Unread incoming messages of this conversation, for the badge.
  final int unreadCount;

  /// Whether the conversation is pinned to the top of the list.
  final bool pinned;

  /// Instant up to which the peer read this chat; null when the chat does not
  /// publish receipts or they never read it.
  final DateTime? peerReadAt;

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  @override
  void initState() {
    super.initState();
    PresenceNotifier.instance.addListener(_onPresenceChanged);
  }

  @override
  void dispose() {
    PresenceNotifier.instance.removeListener(_onPresenceChanged);
    super.dispose();
  }

  /// Presence and typing are ephemeral, so the row redraws on every change.
  void _onPresenceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

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
    // Same rule as the bubble's tick, so the row and the chat cannot disagree.
    final bool seenByPeer = widget.lastMessage.isMe &&
        widget.peerReadAt != null &&
        !widget.lastMessage.sentAt.isAfter(widget.peerReadAt!);

    return ListTile(
      onTap: widget.onPressed,
      tileColor: Colors.transparent,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
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
          // The dot is the whole status badge: presence is opt-in, so an
          // absent dot means "not sharing", not "offline".
          if (PresenceNotifier.instance.isOnline(widget.user.id) == true)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
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
      subtitle: Row(
        children: [
          // The last own message carries the peer's tick, the way the bubble
          // does; a row that hides it makes "delivered" and "read" look alike.
          if (seenByPeer)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.done_all,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          Expanded(
            child: Text(
              // A typing peer outranks the last message; it clears itself.
              PresenceNotifier.instance.isTyping(widget.user.id)
                  ? 'typing'.tr()
                  : getTitle(),
              overflow: TextOverflow.ellipsis,
              style:
                  unread ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
        ],
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
