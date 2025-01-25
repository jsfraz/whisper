import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/color_utils.dart';

class UserListItem extends StatefulWidget {
  const UserListItem(this.user, this.onPressed, {super.key});

  final User user;
  final Function() onPressed;

  @override
  State<UserListItem> createState() => _UserListItemState();
}

class _UserListItemState extends State<UserListItem> {
  @override
  Widget build(BuildContext context) {
    Color userColor = ColorUtils.getColorFromUsername(widget.user.username);

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
      title: Text(widget.user.username),
    );
  }
}
