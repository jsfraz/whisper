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
  const ParsedTextEnvelope(this.body, this.reply, {this.forwarded = false});

  final String body;
  final ReplyRef? reply;

  /// The sender passed on somebody else's text instead of writing it.
  final bool forwarded;
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
    {bool forwarded = false}) {
  final map = <String, dynamic>{
    'whisperMsg': textEnvelopeVersion,
    'kind': 'text',
    'body': body,
    if (reply != null) 'replyTo': reply.toJson(),
    if (forwarded) 'forwarded': true,
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
        decoded['whisperMsg'] == textEnvelopeVersion) {
      final body = decoded['body'];
      if (body is! String) {
        return null;
      }
      return ParsedTextEnvelope(
        body,
        ReplyRef.fromJson(decoded['replyTo']),
        forwarded: decoded['forwarded'] == true,
      );
    }
  } catch (_) {
    // Not JSON / not a text envelope -> plain text.
  }
  return null;
}
