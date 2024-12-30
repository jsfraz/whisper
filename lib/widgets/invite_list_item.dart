import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:whisper_openapi_client/api.dart';

class InviteListItem extends StatefulWidget {
  const InviteListItem(this.invite, {super.key});

  final ModelsInvite invite;

  @override
  State<InviteListItem> createState() => _UserListItemState();
}

class _UserListItemState extends State<InviteListItem> {
  late Timer _timer;
  late Duration _remainingTime;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.invite.validUntil.difference(DateTime.now());

    // Start the timer to update every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingTime = widget.invite.validUntil.difference(DateTime.now());
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Stop when remaining time is negative
    if (_remainingTime.isNegative) {
      _timer.cancel();
    }
    // Calculate absolute remaining time
    Duration displayDuration = _remainingTime;
    // Format display time
    String displayTime =
        displayDuration.toString().split('.').first.padLeft(8, '0');

    return ListTile(
      title: Text(widget.invite.mail),
      trailing: Transform.scale(
        scale: 1.3,
        child: Text(
          _remainingTime.isNegative ? 'inviteExpired'.tr() : displayTime,
          style: TextStyle(
            color: _remainingTime.isNegative
                ? Colors.red
                : Theme.of(context).colorScheme.secondary,
            fontWeight:
                _remainingTime.isNegative ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
