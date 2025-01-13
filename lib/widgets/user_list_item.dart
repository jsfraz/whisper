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
    // Get color of user profile picture
    Color userColor = ColorUtils.getColorFromUsername(widget.user.username);

    // TODO effect onPressed
    // TODO onPressed
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: userColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            widget.user.username.isNotEmpty
                ? widget.user.username[0].toUpperCase()
                : '?',
            style: TextStyle(
              color: ColorUtils.getReadableColor(userColor),
              fontSize: 20,
            ),
          ),
        ),
      ),
      title: Text(widget.user.username),
    );
  }
}
