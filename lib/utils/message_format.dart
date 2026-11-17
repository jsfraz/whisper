import 'link_utils.dart';

/// Inline formatting of a message body.
///
/// The subset the app supports: `**bold**`, `*italic*`, `~~strike~~`,
/// `` `mono` ``, ```` ```block``` ```` and `||spoiler||`. Markers do not nest:
/// the first one that closes wins, which keeps the parser small and the result
/// predictable.
enum MessageStyle {
  plain,
  bold,
  italic,
  strike,

  /// Inline monospace (single backticks).
  mono,

  /// Fenced code block (triple backticks) on its own lines.
  code,

  /// Hidden until tapped.
  spoiler,
}

/// What a piece of a message is, for tap handling.
enum MessageKind {
  text,

  /// Opens in the browser.
  link,

  /// Opens the mail client.
  email,

  /// Tapped to copy.
  phone,

  /// Tapped to copy.
  address,
}

/// One run of message text with one style and one tap action.
class MessagePiece {
  const MessagePiece(this.text, this.style, this.kind);

  final String text;
  final MessageStyle style;
  final MessageKind kind;
}

/// Splits [text] into styled, tappable pieces, in order.
List<MessagePiece> parseMessage(String text) {
  if (text.isEmpty) {
    return const [];
  }
  final pieces = <MessagePiece>[];
  for (final segment in _splitCodeBlocks(text)) {
    if (segment.block) {
      pieces
          .add(MessagePiece(segment.text, MessageStyle.code, MessageKind.text));
    } else {
      _parseInline(segment.text, pieces);
    }
  }
  return pieces;
}

/// Whether [text] is only emoji, so it can be shown large and without a bubble.
///
/// Keycaps (`1️⃣`) and skin-tone modifiers count as emoji. More than
/// [maxLargeEmoji] emoji are still emoji-only, the caller decides the size.
bool isEmojiOnly(String text) {
  var emoji = 0;
  var significant = 0;
  for (final rune in text.runes) {
    if (_isEmojiIgnorable(rune)) {
      continue;
    }
    significant++;
    if (_isEmojiRune(rune) || _isKeycapBase(rune)) {
      if (_isEmojiRune(rune)) {
        emoji++;
      }
      continue;
    }
    return false;
  }
  return emoji > 0 && significant > 0;
}

/// Emoji in a message: used to cap the large rendering.
int emojiCount(String text) => text.runes.where(_isEmojiRune).length;

// Whitespace, variation selectors, ZWJ and skin-tone modifiers carry no
// meaning on their own.
bool _isEmojiIgnorable(int rune) =>
    rune == 0x20 ||
    rune == 0x09 ||
    rune == 0x0A ||
    rune == 0x0D ||
    rune == 0xFE0F ||
    rune == 0xFE0E ||
    rune == 0x200D ||
    (rune >= 0x1F3FB && rune <= 0x1F3FF);

bool _isEmojiRune(int rune) =>
    (rune >= 0x1F000 && rune <= 0x1FAFF) ||
    (rune >= 0x2600 && rune <= 0x27BF) ||
    (rune >= 0x2B00 && rune <= 0x2BFF) ||
    (rune >= 0x1F1E6 && rune <= 0x1F1FF) ||
    rune == 0x2764 ||
    rune == 0x203C ||
    rune == 0x2049;

// Digits, `#` and `*` only appear in emoji when a keycap follows.
bool _isKeycapBase(int rune) =>
    rune == 0x23 || rune == 0x2A || (rune >= 0x30 && rune <= 0x39);

class _Segment {
  const _Segment(this.text, {required this.block});
  final String text;
  final bool block;
}

/// Splits fenced code blocks out of [text]. An unterminated fence runs to the
/// end of the message.
List<_Segment> _splitCodeBlocks(String text) {
  const fence = '```';
  final segments = <_Segment>[];
  var index = 0;
  while (true) {
    final start = text.indexOf(fence, index);
    if (start < 0) {
      segments.add(_Segment(text.substring(index), block: false));
      break;
    }
    segments.add(_Segment(text.substring(index, start), block: false));
    final end = text.indexOf(fence, start + fence.length);
    if (end < 0) {
      segments.add(_Segment(_trimFence(text.substring(start + fence.length)),
          block: true));
      break;
    }
    segments.add(_Segment(_trimFence(text.substring(start + fence.length, end)),
        block: true));
    index = end + fence.length;
  }
  return segments.where((s) => s.block || s.text.isNotEmpty).toList();
}

// The newline that wraps a fence is part of the syntax, not the code.
String _trimFence(String text) {
  var value = text;
  while (value.startsWith('\n')) {
    value = value.substring(1);
  }
  while (value.endsWith('\n')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

class _Marker {
  const _Marker(this.token, this.style);
  final String token;
  final MessageStyle style;
}

// Longest first: `**` must win over `*` at the same position.
const List<_Marker> _markers = [
  _Marker('**', MessageStyle.bold),
  _Marker('~~', MessageStyle.strike),
  _Marker('||', MessageStyle.spoiler),
  _Marker('`', MessageStyle.mono),
  _Marker('*', MessageStyle.italic),
];

void _parseInline(String text, List<MessagePiece> out) {
  final plain = StringBuffer();
  var index = 0;
  while (index < text.length) {
    _Marker? marker;
    var at = -1;
    for (final candidate in _markers) {
      final found = text.indexOf(candidate.token, index);
      if (found >= 0 && (at < 0 || found < at)) {
        marker = candidate;
        at = found;
      }
    }
    if (marker == null) {
      plain.write(text.substring(index));
      break;
    }
    final contentStart = at + marker.token.length;
    final close = text.indexOf(marker.token, contentStart);
    if (close <= contentStart) {
      // No closing marker (or nothing between them): keep the text literal.
      plain.write(text.substring(index, contentStart));
      index = contentStart;
      continue;
    }
    plain.write(text.substring(index, at));
    _flushPlain(plain, out);
    out.add(MessagePiece(
        text.substring(contentStart, close), marker.style, MessageKind.text));
    index = close + marker.token.length;
  }
  _flushPlain(plain, out);
}

void _flushPlain(StringBuffer buffer, List<MessagePiece> out) {
  if (buffer.isEmpty) {
    return;
  }
  out.addAll(_splitEntities(buffer.toString()));
  buffer.clear();
}

/// Splits plain text into links, e-mail addresses, phone numbers, addresses and
/// leftover text.
List<MessagePiece> _splitEntities(String text) {
  final pieces = <MessagePiece>[];
  for (final link in splitLinks(text)) {
    if (link.url != null) {
      pieces.add(MessagePiece(link.text, MessageStyle.plain, MessageKind.link));
      continue;
    }
    pieces.addAll(_splitTappable(link.text));
  }
  return pieces;
}

/// Splits plain text into the things a tap can act on. When two patterns start
/// at the same character the one listed first wins.
List<MessagePiece> _splitTappable(String text) {
  final patterns = <(RegExp, MessageKind)>[
    (_emailPattern, MessageKind.email),
    (_addressPattern, MessageKind.address),
    (_phonePattern, MessageKind.phone),
  ];
  final pieces = <MessagePiece>[];
  var index = 0;
  while (index < text.length) {
    final rest = text.substring(index);
    Match? best;
    var kind = MessageKind.text;
    for (final (pattern, candidateKind) in patterns) {
      final match = pattern.firstMatch(rest);
      if (match == null) {
        continue;
      }
      if (candidateKind == MessageKind.phone &&
          !_isPhoneNumber(match.group(0)!)) {
        continue;
      }
      if (best == null || match.start < best.start) {
        best = match;
        kind = candidateKind;
      }
    }
    if (best == null) {
      pieces.add(MessagePiece(
          text.substring(index), MessageStyle.plain, MessageKind.text));
      break;
    }
    if (best.start > 0) {
      pieces.add(MessagePiece(text.substring(index, index + best.start),
          MessageStyle.plain, MessageKind.text));
    }
    pieces.add(MessagePiece(best.group(0)!, MessageStyle.plain, kind));
    index += best.end;
  }
  return pieces;
}

/// A single address, no display name and no surrounding punctuation.
final RegExp _emailPattern = RegExp(
  r'(?<![\w.+\-])[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+',
);

/// `Street 12, City` — a house number followed by a named place. Requiring the
/// comma keeps ordinary "version 2" text from turning into an address.
final RegExp _addressPattern = RegExp(
  r'[\p{Lu}][\p{L}.]{1,}(?:\s+[\p{L}.]+){0,3}\s+\d+[a-zA-Z]?(?:/\d+)?,\s*[\p{Lu}][\p{L}]*(?:\s+[\p{L}]+)*',
  unicode: true,
);

/// Digits with the usual grouping separators. Filtered by digit count below,
/// which is what keeps a year or a price out.
final RegExp _phonePattern =
    RegExp(r'(?<![\w])\+?\d[\d\s()+.\-]{4,}\d(?![\w])');

bool _isPhoneNumber(String candidate) {
  final digits = candidate.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 7 && digits.length <= 15;
}
