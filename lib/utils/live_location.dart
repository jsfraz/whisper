import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user.dart';
import 'crypto_utils.dart';
import 'singleton.dart';

/// One live position as the peer sees it: where, and until when.
class LiveLocationPoint {
  final double lat;
  final double lng;
  final double? accuracy;
  final DateTime until;

  const LiveLocationPoint(this.lat, this.lng,
      {this.accuracy, required this.until});

  String get coordinates =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  factory LiveLocationPoint.fromJson(Map<String, dynamic> json) {
    return LiveLocationPoint(
      (json['lat'] as num).toDouble(),
      (json['lng'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      until: DateTime.parse(json['until'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        'until': until.toUtc().toIso8601String(),
      };
}

/// Wraps the four parts of one hybrid-encrypted position into one string the
/// WebSocket frame can carry. The server relays it and sees no coordinates.
String encodeEncryptedPayload(Map<String, Uint8List> data) {
  return base64Encode(utf8.encode(jsonEncode({
    'data': base64Encode(data['encryptedData']!),
    'key': base64Encode(data['encryptedKey']!),
    'nonce': base64Encode(data['nonce']!),
    'mac': base64Encode(data['mac']!),
  })));
}

/// Reverses [encodeEncryptedPayload]; null for anything malformed.
Map<String, Uint8List>? decodeEncryptedPayload(String payload) {
  try {
    final raw = jsonDecode(utf8.decode(base64Decode(payload)));
    if (raw is! Map) {
      return null;
    }
    return {
      'encryptedData': base64Decode(raw['data'] as String),
      'encryptedKey': base64Decode(raw['key'] as String),
      'nonce': base64Decode(raw['nonce'] as String),
      'mac': base64Decode(raw['mac'] as String),
    };
  } catch (_) {
    return null;
  }
}

/// Decrypts one relayed position with this device's key.
Future<LiveLocationPoint?> decryptLiveLocation(String payload) async {
  final parts = decodeEncryptedPayload(payload);
  if (parts == null) {
    return null;
  }
  try {
    final plain = await CryptoUtils.decryptMessageData(
        parts['encryptedData']!,
        parts['encryptedKey']!,
        parts['nonce']!,
        parts['mac']!,
        bu.CryptoUtils.rsaPrivateKeyFromPem(Singleton().profile.privateKey));
    return LiveLocationPoint.fromJson(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map));
  } catch (_) {
    return null;
  }
}

/// Shares this device's position for a limited time. Nothing is archived: the
/// frames stop at the deadline, and the peer keeps only the last point in
/// memory.
class LiveLocationSharer {
  LiveLocationSharer._();

  static final LiveLocationSharer instance = LiveLocationSharer._();

  /// How often a fresh position is sent while sharing.
  static const Duration interval = Duration(seconds: 10);

  Timer? _timer;
  String? _peerId;
  DateTime? _until;

  bool isSharing(String peerId) => _timer != null && _peerId == peerId;

  DateTime? get until => _until;

  /// Starts a session with [peer]. Returns false when there is no fix, which is
  /// also what a refused permission looks like.
  Future<bool> start(User peer, Duration duration) async {
    await stop();
    final position = await currentPosition();
    if (position == null) {
      await Fluttertoast.showToast(
          msg: 'locationUnavailable'.tr(), backgroundColor: Colors.red);
      return false;
    }
    _peerId = peer.id;
    _until = DateTime.now().add(duration);
    await _send(peer, position);
    _timer = Timer.periodic(interval, (_) async {
      final next = await currentPosition();
      if (next != null) {
        await _send(peer, next);
      }
      final deadline = _until;
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        await stop();
      }
    });
    return true;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _peerId = null;
    _until = null;
  }

  Future<void> _send(User peer, Position position) async {
    final deadline = _until;
    if (deadline == null || !Singleton().wsClient.isConnected) {
      return;
    }
    final point = LiveLocationPoint(position.latitude, position.longitude,
        accuracy: position.accuracy, until: deadline);
    try {
      final data = await CryptoUtils.encryptMessageData(
          utf8.encode(jsonEncode(point.toJson())),
          bu.CryptoUtils.rsaPublicKeyFromPem(peer.publicKey));
      Singleton()
          .wsClient
          .sendLiveLocation(peer.id, encodeEncryptedPayload(data));
    } catch (_) {
      // A frame that cannot be encrypted is dropped; the next tick retries.
    }
  }

  /// One fix from the platform, null when the user refused the permission or
  /// location is switched off.
  static Future<Position?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }
}
