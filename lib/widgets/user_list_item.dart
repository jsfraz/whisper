import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/presence.dart';

class UserListItem extends StatefulWidget {
  const UserListItem(this.user, this.onPressed, {super.key});

  final User user;
  final Function() onPressed;

  @override
  State<UserListItem> createState() => _UserListItemState();
}

class _UserListItemState extends State<UserListItem> {
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

  /// Presence is ephemeral, so the row redraws on every change.
  void _onPresenceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
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
          // Same badge as the chat list: an absent dot means "not sharing".
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
      title: Text(widget.user.username),
    );
  }
}
