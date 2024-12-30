import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/color_utils.dart';

class UserListItem extends StatefulWidget {
  const UserListItem(this.user, this.valueChanged, {super.key});

  final User user;
  final Function(bool) valueChanged;

  @override
  State<UserListItem> createState() => _UserListItemState();
}

class _UserListItemState extends State<UserListItem> {
  bool isSelected = false;

  @override
  Widget build(BuildContext context) {
    // Get color of user profile picture
    Color userColor =
        ColorUtils.getColorFromUsername(widget.user.username);

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
            widget.user.username.isNotEmpty ? widget.user.username[0].toUpperCase() : '?',
            style: TextStyle(
              color: ColorUtils.getReadableColor(userColor),
              fontSize: 20,
            ),
          ),
        ),
      ),
      title: Text(widget.user.username),
      trailing: Checkbox(
        value: isSelected,
        onChanged: (_) {
          setState(() {
            isSelected = !isSelected;
            widget.valueChanged(isSelected);
          });
        },
      ),
    );
  }
}
