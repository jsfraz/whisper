import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import 'live_location.dart';

/// Live, in-memory status of the other participants: who is online, when they
/// were last seen and whether they are typing. Nothing here is stored, and the
/// server keeps no presence either, so a restart or a disconnect empties it.
class PresenceNotifier extends ChangeNotifier {
  PresenceNotifier._();

  static final PresenceNotifier instance = PresenceNotifier._();

  /// How long a typing hint stays visible after the last frame. The sender
  /// repeats it while typing, so there is no "stopped typing" frame.
  Duration typingTtl = const Duration(seconds: 5);

  /// How long an "online" stays believable without a new announcement. The
  /// sender repeats it every minute, so an app that is killed instead of paused
  /// drops off on its own.
  Duration presenceTtl = const Duration(seconds: 95);

  final Map<String, DateTime> _lastSeen = {};
  final Map<String, Timer> _presenceTimers = {};
  final Map<String, DateTime> _typingUntil = {};
  final Map<String, Timer> _typingTimers = {};
  final Map<String, bool> _online = {};

  /// Live positions shared with this device, dropped at their own deadline.
  final Map<String, LiveLocationPoint> _live = {};
  final Map<String, Timer> _liveTimers = {};

  /// The position [peerId] is sharing right now, null when they are not.
  LiveLocationPoint? liveLocation(String peerId) {
    final point = _live[peerId];
    if (point == null || point.until.isBefore(DateTime.now())) {
      return null;
    }
    return point;
  }

  /// Keeps one relayed position and forgets it at its deadline.
  void applyLiveLocation(String peerId, LiveLocationPoint point) {
    _live[peerId] = point;
    _liveTimers.remove(peerId)?.cancel();
    final left = point.until.difference(DateTime.now());
    _liveTimers[peerId] = Timer(left.isNegative ? Duration.zero : left, () {
      _live.remove(peerId);
      _liveTimers.remove(peerId);
      notifyListeners();
    });
    notifyListeners();
  }

  /// True when [peerId] is known to be online; null when nothing is known.
  bool? isOnline(String peerId) => _online[peerId];

  /// When [peerId] was last seen, null while unknown.
  DateTime? lastSeen(String peerId) => _lastSeen[peerId];

  /// Whether [peerId] is typing right now.
  bool isTyping(String peerId) {
    final until = _typingUntil[peerId];
    return until != null && until.isAfter(DateTime.now());
  }

  /// Applies one presence frame. Going offline carries the instant the server
  /// saw it, which is the only last seen this client ever gets.
  void applyPresence(String peerId,
      {required bool online, DateTime? lastSeenAt}) {
    _online[peerId] = online;
    _presenceTimers.remove(peerId)?.cancel();
    if (online) {
      _lastSeen.remove(peerId);
      _presenceTimers[peerId] = Timer(presenceTtl, () {
        // Silence means the peer lost the network or was killed: nobody will
        // announce it, so the badge expires instead of lying.
        _online[peerId] = false;
        _lastSeen[peerId] = DateTime.now();
        _presenceTimers.remove(peerId);
        notifyListeners();
      });
    } else if (lastSeenAt != null) {
      _lastSeen[peerId] = lastSeenAt.toLocal();
    }
    notifyListeners();
  }

  /// Applies one typing hint and clears it again on its own after
  /// [typingTtl].
  void applyTyping(String peerId) {
    _typingUntil[peerId] = DateTime.now().add(typingTtl);
    _typingTimers.remove(peerId)?.cancel();
    _typingTimers[peerId] = Timer(typingTtl, () {
      _typingUntil.remove(peerId);
      _typingTimers.remove(peerId);
      notifyListeners();
    });
    notifyListeners();
  }

  /// Drops everything: without a connection nothing here is known anymore.
  void clear() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    for (final timer in _presenceTimers.values) {
      timer.cancel();
    }
    for (final timer in _liveTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _presenceTimers.clear();
    _liveTimers.clear();
    _typingUntil.clear();
    _online.clear();
    _lastSeen.clear();
    _live.clear();
    notifyListeners();
  }

  /// One line under a name: typing wins over online, online over last seen.
  /// Null when nothing is known, so the caller keeps the plain name.
  String? statusText(String peerId) {
    if (isTyping(peerId)) {
      return 'typing'.tr();
    }
    if (_online[peerId] == true) {
      return 'online'.tr();
    }
    final seen = _lastSeen[peerId];
    if (seen != null) {
      return 'lastSeenAt'.tr(args: [DateFormat.Hm().format(seen)]);
    }
    return null;
  }
}
