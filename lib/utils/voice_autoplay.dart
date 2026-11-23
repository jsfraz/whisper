import 'package:flutter/foundation.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import 'cache_utils.dart';

/// Chains voice messages: when one finishes, the next one of the same chat
/// starts.
///
/// The request is the key of the message that should play, and only the player
/// owning that key picks it up, so no bubble has to reach into another one.
class VoiceAutoplay {
  VoiceAutoplay._();

  /// Key of the message that should start playing, consumed by its player.
  static final ValueNotifier<String?> request = ValueNotifier<String?>(null);

  /// Asks the next voice message after [afterSentAt] in [conversationId] to
  /// play.
  ///
  /// The chain is for listening to the other side: it stops at our own voice
  /// message instead of playing it back. It also stops at the end of the chat,
  /// and skips a message that is not on this device, since that one could not
  /// play anyway.
  ///
  /// shortcut: a player only exists while its bubble is built, so a request for
  /// an off-screen message is dropped; upgrade by hoisting playback into a
  /// service that owns the queue.
  static Future<void> next(String conversationId, DateTime afterSentAt) async {
    final messages = await CacheUtils.getPrivateMessages(conversationId);
    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    for (final message in messages) {
      if (!message.sentAt.isAfter(afterSentAt)) {
        continue;
      }
      if (message.mediaType != MediaType.voice) {
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
