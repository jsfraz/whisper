import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../utils/live_location.dart';
import '../utils/message_actions.dart';
import '../utils/presence.dart';
import '../utils/text_envelope.dart';

/// One row above the composer while a live location is on: this device's with a
/// stop button, the peer's with the last point and a way into the map app.
class LiveLocationBanner extends StatefulWidget {
  final User peer;

  const LiveLocationBanner(this.peer, {super.key});

  @override
  State<LiveLocationBanner> createState() => _LiveLocationBannerState();
}

class _LiveLocationBannerState extends State<LiveLocationBanner> {
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
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.my_location, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  until == null ? label : '$label · ${_left(until)}',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
                if (!mine)
                  GestureDetector(
                    onTap: () {
                      final point = theirs;
                      if (point != null) {
                        MessageActions.openLocation(
                            LocationRef(point.lat, point.lng));
                      }
                    },
                    child: Text(
                      theirs?.coordinates ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (mine)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'liveLocationStop'.tr(),
              onPressed: () async {
                await LiveLocationSharer.instance.stop();
                if (mounted) {
                  setState(() {});
                }
              },
            ),
        ],
      ),
    );
  }
}
