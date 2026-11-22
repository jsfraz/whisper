import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../utils/live_location.dart';
import '../utils/message_actions.dart';
import '../utils/presence.dart';
import '../utils/text_envelope.dart';

/// The live view of one shared location: the last position, its accuracy and the
/// time left, updated in place. No tiles are fetched, so the coordinates stay on
/// the device until the map button is tapped.
class LiveLocationPage extends StatefulWidget {
  const LiveLocationPage(this.peer, {super.key});

  final User peer;

  @override
  State<LiveLocationPage> createState() => _LiveLocationPageState();
}

class _LiveLocationPageState extends State<LiveLocationPage> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
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
    final point = theirs;
    final until = mine ? LiveLocationSharer.instance.until : point?.until;
    final scheme = Theme.of(context).colorScheme;
    final active = mine || point != null;
    final lat = point?.lat;
    final lng = point?.lng;

    return Scaffold(
      appBar: AppBar(title: Text(widget.peer.username)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.my_location, size: 72, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  mine ? 'liveLocationMine'.tr() : 'liveLocationTheirs'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (until != null) ...[
                  const SizedBox(height: 4),
                  Text(_left(until),
                      style: Theme.of(context).textTheme.headlineSmall),
                ],
                if (point != null) ...[
                  const SizedBox(height: 12),
                  Text(point.coordinates,
                      style: Theme.of(context).textTheme.bodyLarge),
                  if (point.accuracy != null)
                    Text('± ${point.accuracy!.round()} m',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
                if (!active) ...[
                  const SizedBox(height: 12),
                  Text('liveLocationEnded'.tr(),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 24),
                if (lat != null && lng != null)
                  FilledButton.icon(
                    onPressed: () => MessageActions.openLocation(
                        LocationRef(lat, lng, accuracy: point?.accuracy)),
                    icon: const Icon(Icons.map),
                    label: Text('openInMaps'.tr()),
                  ),
                if (mine) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      await LiveLocationSharer.instance.stop();
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text('liveLocationStop'.tr()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
