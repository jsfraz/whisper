import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sprintf/sprintf.dart';
import 'package:shept_openapi_client_dart/api.dart';

import '../utils/admin_format.dart';

/// One row of the admin invite list: the invited address and how long the
/// invitation is still valid. Mostly static, so it only rebuilds per minute.
class InviteListItem extends StatefulWidget {
  const InviteListItem(this.invite, {super.key});

  final ModelsInvite invite;

  @override
  State<InviteListItem> createState() => _InviteListItemState();
}

class _InviteListItemState extends State<InviteListItem> {
  Timer? _timer;
  late Duration _remainingTime;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.invite.validUntil.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          _remainingTime = widget.invite.validUntil.difference(DateTime.now());
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final remaining = inviteRemaining(_remainingTime);
    return ListTile(
      tileColor: Colors.transparent,
      title: Text(widget.invite.mail, overflow: TextOverflow.ellipsis),
      trailing: Text(
        remaining == null
            ? 'inviteExpired'.tr()
            : sprintf(
                'inviteExpiresIn'.tr(), ['${remaining.value}', remaining.unit]),
        style: TextStyle(
          fontSize: 12,
          color: remaining == null ? Colors.red : colors.secondary,
          fontWeight: remaining == null ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
