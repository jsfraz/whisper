import 'package:flutter/foundation.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import '../models/private_message.dart';
import 'cache_utils.dart';

/// Chains messages that play on their own: when one finishes, the next one of
/// the same chat starts.
///
/// The request is the key of the message that should play, and only the player
/// owning that key picks it up, so no bubble has to reach into another one.
class MediaAutoplay {
  MediaAutoplay._();

  /// Key of the message that should start playing, consumed by its player.
  static final ValueNotifier<String?> request = ValueNotifier<String?>(null);

  /// Asks the next voice message after [afterSentAt] in [conversationId] to
  /// play.
  static Future<void> next(String conversationId, DateTime afterSentAt) =>
      _next(conversationId, afterSentAt,
          (message) => message.mediaType == MediaType.voice);

  /// Asks the next round note after [afterSentAt] in [conversationId] to play.
  static Future<void> nextRoundNote(
          String conversationId, DateTime afterSentAt) =>
      _next(conversationId, afterSentAt, (message) => message.isVideoNote);

  /// The chain is for listening to the other side: it stops at our own message
  /// instead of playing it back. It also stops at the end of the chat, and
  /// skips a message that is not on this device, since that one could not play
  /// anyway.
  ///
  /// shortcut: a player only exists while its bubble is built, so a request for
  /// an off-screen message is dropped; upgrade by hoisting playback into a
  /// service that owns the queue.
  static Future<void> _next(String conversationId, DateTime afterSentAt,
      bool Function(PrivateMessage message) matches) async {
    final messages = await CacheUtils.getPrivateMessages(conversationId);
    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    for (final message in messages) {
      if (!message.sentAt.isAfter(afterSentAt)) {
        continue;
      }
      if (!matches(message)) {
        continue;
      }
      // Our own message ends the chain: playback continues only into what the
      // other side said.
      if (message.isMe) {
        return;
      }
      if (message.localPath == null) {
        continue;
      }
      request.value = CacheUtils.messageKey(conversationId, message.sentAt);
      return;
    }
  }
}
