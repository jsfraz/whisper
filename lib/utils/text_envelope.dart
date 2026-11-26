import 'dart:convert';
import 'dart:typed_data';

/// The message a reply quotes.
///
/// The preview is stored next to the pointer, so the quote still reads after
/// the original was deleted locally (deleting a message only removes it on
/// this device).
class ReplyRef {
  const ReplyRef({
    required this.senderId,
    required this.sentAt,
    required this.preview,
  });

  final String senderId;
  final DateTime sentAt;

  /// Truncated body of the quoted message.
  final String preview;

  /// Longest preview kept in the envelope; the bubble shows two lines.
  static const int maxPreviewLength = 160;

  Map<String, dynamic> toJson() => {
        'senderId': senderId,
        'sentAt': sentAt.microsecondsSinceEpoch,
        'preview': preview,
      };

  /// Null when [json] is not a usable reference.
  static ReplyRef? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final senderId = json['senderId'];
    final sentAt = json['sentAt'];
    if (senderId is! String || sentAt is! int) {
      return null;
    }
    return ReplyRef(
      senderId: senderId,
      sentAt: DateTime.fromMicrosecondsSinceEpoch(sentAt),
      preview: json['preview'] is String ? json['preview'] as String : '',
    );
  }

  /// Shortens [text] for storage in the envelope.
  static String previewOf(String text) => text.length <= maxPreviewLength
      ? text
      : '${text.substring(0, maxPreviewLength)}…';
}

/// Payload of a text message that quotes another one.
class ParsedTextEnvelope {
  const ParsedTextEnvelope(this.body, this.reply,
      {this.forwarded = false, this.location, this.viewOnce = false});

  final String body;
  final ReplyRef? reply;

  /// The sender passed on somebody else's text instead of writing it.
  final bool forwarded;

  /// A static location, null for an ordinary text message.
  final LocationRef? location;

  /// A single-view message: the body is revealed once and then burnt. Only a
  /// location uses it; an attachment carries the flag in its media envelope.
  final bool viewOnce;
}

/// A static location inside a text envelope. It stays a `text` message with an
/// optional key, so an older client shows the body ("📍 50.08, 14.42") instead
/// of raw JSON.
class LocationRef {
  final double lat;
  final double lng;
  final double? accuracy;
  final String? label;

  const LocationRef(this.lat, this.lng, {this.accuracy, this.label});

  /// What a client without location support still shows.
  String get body => '📍 ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        if (label != null && label!.isNotEmpty) 'label': label,
      };

  static LocationRef? fromJson(dynamic json) {
    if (json is! Map) {
      return null;
    }
    final lat = json['lat'];
    final lng = json['lng'];
    if (lat is! num || lng is! num) {
      return null;
    }
    return LocationRef(lat.toDouble(), lng.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        label: json['label'] as String?);
  }
}

/// Envelope version of a text message carrying a quote. Versions 1 and 2 are
/// the media envelopes; plain text stays raw UTF-8, so a reader that never
/// quotes anything keeps writing what every older client can open.
const int textEnvelopeVersion = 3;

/// Plaintext (pre-encryption) bytes of a reply or a forwarded message.
///
/// The envelope stays version 3 and the flags are optional keys, so a reader
/// that predates them still shows the body instead of raw JSON.
Uint8List buildTextEnvelope(String body, ReplyRef? reply,
    {bool forwarded = false, LocationRef? location, bool viewOnce = false}) {
  final map = <String, dynamic>{
    'sheptMsg': textEnvelopeVersion,
    'kind': 'text',
    'body': body,
    if (reply != null) 'replyTo': reply.toJson(),
    if (forwarded) 'forwarded': true,
    if (location != null) 'location': location.toJson(),
    if (viewOnce) 'viewOnce': true,
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(map)));
}

/// Parses [plaintext] as a quoting text envelope. Null for anything else, which
/// includes every plain text message.
ParsedTextEnvelope? tryParseTextEnvelope(Uint8List plaintext) {
  try {
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is Map &&
        decoded['kind'] == 'text' &&
        decoded['sheptMsg'] == textEnvelopeVersion) {
      final body = decoded['body'];
      if (body is! String) {
        return null;
      }
      return ParsedTextEnvelope(
        body,
        ReplyRef.fromJson(decoded['replyTo']),
        forwarded: decoded['forwarded'] == true,
        location: LocationRef.fromJson(decoded['location']),
        viewOnce: decoded['viewOnce'] == true,
      );
    }
  } catch (_) {
    // Not JSON / not a text envelope -> plain text.
  }
  return null;
}

/// Envelope version of a control message: a chat setting both participants have
/// to agree on. It has its own version and kind, so no reader mistakes it for
/// text; a client that predates it shows raw JSON, which is why a timer is only
/// proposed towards a peer already on the new build.
const int systemEnvelopeVersion = 4;

/// The only control message so far: the disappearing-message timer.
const String systemActionDisappearing = 'disappearing';

class ParsedSystemEnvelope {
  const ParsedSystemEnvelope(this.state, this.seconds);

  /// "propose", "accept" or "decline".
  final String state;

  /// The timer in seconds; 0 turns disappearing messages off.
  final int seconds;
}

/// Plaintext (pre-encryption) bytes of a disappearing-message proposal, an
/// acceptance or a refusal.
Uint8List buildSystemEnvelope(String state, int seconds) {
  final map = <String, dynamic>{
    'sheptMsg': systemEnvelopeVersion,
    'kind': 'system',
    'action': systemActionDisappearing,
    'state': state,
    'seconds': seconds,
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(map)));
}

/// Parses [plaintext] as a control envelope. Null for anything else.
ParsedSystemEnvelope? tryParseSystemEnvelope(Uint8List plaintext) {
  try {
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map ||
        decoded['kind'] != 'system' ||
        decoded['sheptMsg'] != systemEnvelopeVersion ||
        decoded['action'] != systemActionDisappearing) {
      return null;
    }
    final state = decoded['state'];
    final seconds = decoded['seconds'];
    if (state is! String || seconds is! num) {
      return null;
    }
    if (state != 'propose' && state != 'accept' && state != 'decline') {
      return null;
    }
    return ParsedSystemEnvelope(state, seconds.toInt());
  } catch (_) {
    return null;
  }
}
