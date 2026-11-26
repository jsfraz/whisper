import '../models/private_message.dart';

/// One stored message that matched a search, with the conversation it belongs
/// to (the other side's user id, not the sender: an archived message we sent
/// lives in the peer's conversation).
class MessageHit {
  const MessageHit(this.conversationId, this.message);

  final String conversationId;
  final PrivateMessage message;
}

/// What to look for in one conversation's local history.
///
/// The store holds decrypted text, so a search is a local scan: nothing leaves
/// the device and no server round-trip happens.
class MessageSearchQuery {
  const MessageSearchQuery({this.text = '', this.conversationId});

  /// Case-insensitive substring of the message text (or of a file name).
  final String text;

  /// Restricts the search to one conversation.
  final String? conversationId;

  /// Whether this query filters anything out at all.
  bool get isEmpty => text.trim().isEmpty;

  bool matches(MessageHit hit) {
    if (conversationId != null && hit.conversationId != conversationId) {
      return false;
    }
    final needle = text.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    final message = hit.message;
    // An attachment without a caption is still findable by its file name.
    return message.message.toLowerCase().contains(needle) ||
        (message.fileName ?? '').toLowerCase().contains(needle);
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
