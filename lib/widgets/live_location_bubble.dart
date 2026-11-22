import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../pages/live_location_page.dart';
import '../utils/live_location.dart';
import '../utils/presence.dart';

/// The live location as one bubble in the conversation: this device's or the
/// peer's, ticking with the time left. Tapping it opens the live view; nothing
/// is archived, so the bubble exists only while a session does.
class LiveLocationBubble extends StatefulWidget {
  const LiveLocationBubble(this.peer, {this.showAvatar = true, super.key});

  final User peer;

  /// Whether this bubble closes the peer's run of messages: the avatar is
  /// drawn only there, like on every other bubble.
  final bool showAvatar;

  @override
  State<LiveLocationBubble> createState() => _LiveLocationBubbleState();
}

class _LiveLocationBubbleState extends State<LiveLocationBubble> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The remaining time is a clock, not an event: one rebuild a second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    PresenceNotifier.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    _tick?.cancel();
    PresenceNotifier.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _left(DateTime until) {
    final left = until.difference(DateTime.now());
    if (left.isNegative) {
      return '0:00';
    }
    return '${left.inMinutes}:'
        '${left.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final mine = LiveLocationSharer.instance.isSharing(widget.peer.id);
    final theirs = PresenceNotifier.instance.liveLocation(widget.peer.id);
    if (!mine && theirs == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final until = mine ? LiveLocationSharer.instance.until : theirs?.until;
    final label = mine ? 'liveLocationMine'.tr() : 'liveLocationTheirs'.tr();
    final color = mine ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final textColor =
        mine ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    // Laid out like a message bubble of this chat: the same side, the same
    // width limits and, incoming, the same avatar.
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.my_location, size: 20, color: textColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              until == null ? label : '$label · ${_left(until)}',
              style: TextStyle(color: textColor),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 18, color: textColor),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: mine ? 96 : 16,
        right: mine ? 16 : 96,
        top: 16,
      ),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine && widget.showAvatar)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: widget.peer.avatarColor,
                child: Text(
                  widget.peer.username.isNotEmpty
                      ? widget.peer.username[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.peer.avatarTextColor,
                  ),
                ),
              ),
            ),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LiveLocationPage(widget.peer))),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}
