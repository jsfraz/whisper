import '../models/private_message.dart';
import 'cache_utils.dart';
import 'media_utils.dart';

/// What the attachments of one conversation cost on this device.
class ConversationUsage {
  const ConversationUsage(this.conversationId, this.bytes, this.attachments);

  final String conversationId;
  final int bytes;
  final int attachments;
}

/// Local media accounting, and the two ways to get the space back.
///
/// Attachments are the only thing here that grows without bound: the archive is
/// text, but every video leaves an encrypted copy on disk until something
/// removes it.
class StorageUtils {
  StorageUtils._();

  /// Bytes and attachment count per conversation, newest biggest first.
  static Future<List<ConversationUsage>> usageByConversation() async {
    final messages = await CacheUtils.getAllConversationMessages();
    final usage = <ConversationUsage>[];
    for (final entry in messages.entries) {
      var bytes = 0;
      var count = 0;
      for (final message in entry.value) {
        bytes += _messageBytes(message);
        count += message.localPaths.length;
      }
      if (count > 0) {
        usage.add(ConversationUsage(entry.key, bytes, count));
      }
    }
    usage.sort((a, b) => b.bytes.compareTo(a.bytes));
    return usage;
  }

  /// What one conversation keeps on this device.
  static Future<ConversationUsage> usageFor(String conversationId) async {
    for (final usage in await usageByConversation()) {
      if (usage.conversationId == conversationId) {
        return usage;
      }
    }
    return ConversationUsage(conversationId, 0, 0);
  }

  /// Drops the local copy of every attachment older than [days] and marks it
  /// expired, keeping the messages themselves. Returns the bytes freed.
  ///
  /// The media is single delivery: once dropped it cannot be downloaded again,
  /// which is why the setting spells that out before it is applied.
  static Future<int> purgeOlderThanDays(int days) async {
    if (days <= 0) {
      return 0;
    }
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final messages = await CacheUtils.getAllConversationMessages();
    var freed = 0;
    for (final entry in messages.entries) {
      for (final message in entry.value) {
        if (message.sentAt.isAfter(cutoff)) {
          continue;
        }
        final paths = message.localPaths;
        if (paths.isEmpty) {
          continue;
        }
        freed += _messageBytes(message);
        for (final path in paths) {
          await MediaUtils.deleteLocalFile(path);
        }
        await CacheUtils.updateStoredMessage(entry.key, message, (stored) {
          stored.localPath = null;
          stored.downloadStatus = MediaDownloadStatus.expired;
          if (!stored.isAlbum) {
            return;
          }
          final items = stored.album;
          for (final item in items) {
            if (item.localPath != null) {
              item.localPath = null;
              item.status = MediaDownloadStatus.expired;
            }
          }
          stored.setAlbum(items);
        });
      }
    }
    return freed;
  }

  /// Empties the temporary plaintext files and the in-memory decrypt cache.
  /// The stored attachments stay: only copies that were never meant to outlive
  /// the session go.
  static Future<void> clearCache() async {
    await MediaUtils.clearTempFiles();
    MediaUtils.clearDecryptedCache();
  }

  /// Applies the configured auto-delete once at start-up.
  static Future<void> purgeIfDue() async {
    final days = await CacheUtils.getAutoDeleteMediaDays();
    if (days > 0) {
      await purgeOlderThanDays(days);
    }
  }

  /// Bytes one stored message keeps on disk, including the encryption overhead.
  static int _messageBytes(PrivateMessage message) {
    var bytes = 0;
    if (message.localPath != null) {
      bytes += (message.mediaSize ?? 0) + MediaUtils.transportOverheadBytes;
    }
    for (final item in message.album) {
      if (item.localPath != null) {
        bytes += item.size + MediaUtils.transportOverheadBytes;
      }
    }
    return bytes;
  }
}
