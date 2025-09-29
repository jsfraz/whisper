import 'package:flutter/material.dart';
import '../models/user.dart';

class SelectUserListItem extends StatefulWidget {
  const SelectUserListItem(this.user, this.valueChanged, {super.key});

  final User user;
  final Function(bool) valueChanged;

  @override
  State<SelectUserListItem> createState() => _SelectUserListItemState();
}

class _SelectUserListItemState extends State<SelectUserListItem> {
  bool _isSelected = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {},   // Empty method so that the visual effect works
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
      title: Text(widget.user.username),
      trailing: Checkbox(
        value: _isSelected,
        onChanged: (_) {
          setState(() {
            _isSelected = !_isSelected;
            widget.valueChanged(_isSelected);
          });
        },
      ),
    );
  }
}
