import '../models/private_message.dart';

/// One stored message that matched a search, with the conversation it belongs
/// to (the other side's user id, not the sender: an archived message we sent
/// lives in the peer's conversation).
class MessageHit {
  const MessageHit(this.conversationId, this.message);

  final String conversationId;
  final PrivateMessage message;
}

/// What to look for in the local message store.
///
/// The store holds decrypted text, so a search is a local scan: nothing leaves
/// the device and no server round-trip happens.
class MessageSearchQuery {
  const MessageSearchQuery({
    this.text = '',
    this.conversationId,
    this.from,
    this.to,
    this.type,
  });

  /// Case-insensitive substring of the message text (or of an attachment name).
  final String text;

  /// Restricts the search to one conversation.
  final String? conversationId;

  /// Inclusive start of the date range.
  final DateTime? from;

  /// Inclusive end of the date range: the whole [to] day counts.
  final DateTime? to;

  /// `text`, or a [MediaType.name]; null matches everything.
  final String? type;

  /// Value of [type] for messages without an attachment.
  static const String textType = 'text';

  /// Whether this query filters anything out at all.
  bool get isEmpty =>
      text.trim().isEmpty &&
      type == null &&
      from == null &&
      to == null &&
      conversationId == null;

  bool matches(MessageHit hit) {
    final message = hit.message;
    if (conversationId != null && hit.conversationId != conversationId) {
      return false;
    }
    if (!_matchesType(message)) {
      return false;
    }
    final time = message.sentAt;
    if (from != null && time.isBefore(from!)) {
      return false;
    }
    if (to != null) {
      final endOfDay = DateTime(to!.year, to!.month, to!.day, 23, 59, 59, 999);
      if (time.isAfter(endOfDay)) {
        return false;
      }
    }
    final needle = text.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    // An attachment without a caption is still findable by its file name.
    return message.message.toLowerCase().contains(needle) ||
        (message.fileName ?? '').toLowerCase().contains(needle);
  }

  bool _matchesType(PrivateMessage message) {
    final wanted = type;
    if (wanted == null) {
      return true;
    }
    if (wanted == textType) {
      return !message.isMedia;
    }
    if (message.mediaTypeStr == wanted) {
      return true;
    }
    // An album matches when any of its attachments has the type.
    return message.album.any((item) => item.type == wanted);
  }
}

/// How many hits a search returns. A single letter must not walk the whole
/// history into a list.
const int searchResultLimit = 300;

/// Applies [query] to [hits] and returns the newest first.
List<MessageHit> filterMessages(
    Iterable<MessageHit> hits, MessageSearchQuery query) {
  final matched = hits.where(query.matches).toList()
    ..sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
  return matched.length > searchResultLimit
      ? matched.sublist(0, searchResultLimit)
      : matched;
}

/// A window of [text] around the first occurrence of [needle], for the result
/// list. Returns [text] when the needle is not in it.
String snippet(String text, String needle, {int radius = 40}) {
  final trimmed = needle.trim();
  if (trimmed.isEmpty) {
    return text.length <= radius * 2
        ? text
        : '${text.substring(0, radius * 2)}…';
  }
  final at = text.toLowerCase().indexOf(trimmed.toLowerCase());
  if (at < 0) {
    return text.length <= radius * 2
        ? text
        : '${text.substring(0, radius * 2)}…';
  }
  var start = at - radius;
  var end = at + trimmed.length + radius;
  if (start < 0) {
    start = 0;
  }
  if (end > text.length) {
    end = text.length;
  }
  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  return '$prefix${text.substring(start, end)}$suffix';
}

/// Splits [text] into alternating plain and matched runs, so a result can show
/// what it found. Case-insensitive; every occurrence is marked.
List<({String text, bool match})> highlightParts(String text, String needle) {
  final plain = [(text: text, match: false)];
  final trimmed = needle.trim();
  if (trimmed.isEmpty || text.isEmpty) {
    return plain;
  }
  final lowered = text.toLowerCase();
  final target = trimmed.toLowerCase();
  final parts = <({String text, bool match})>[];
  var index = 0;
  while (true) {
    final at = lowered.indexOf(target, index);
    if (at < 0) {
      if (index < text.length) {
        parts.add((text: text.substring(index), match: false));
      }
      break;
    }
    if (at > index) {
      parts.add((text: text.substring(index, at), match: false));
    }
    parts.add((text: text.substring(at, at + target.length), match: true));
    index = at + target.length;
  }
  return parts.isEmpty ? plain : parts;
}
