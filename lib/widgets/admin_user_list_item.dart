import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';

/// One row of the admin user list: avatar, name, admin badge and the
/// destructive action in an overflow menu.
class AdminUserListItem extends StatelessWidget {
  const AdminUserListItem(this.user, {required this.onDelete, super.key});

  final User user;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      tileColor: Colors.transparent,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: user.avatarColor,
        child: Text(
          user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
          style: TextStyle(fontSize: 20, color: user.avatarTextColor),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(user.username, overflow: TextOverflow.ellipsis),
          ),
          if (user.admin)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'adminBadge'.tr(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (_) => onDelete(),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_forever, color: Colors.red),
                const SizedBox(width: 8),
                Text('deleteUser'.tr(),
                    style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
