import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shept_websocket_client_dart/models/media_reference.dart';
import 'package:shept_websocket_client_dart/models/media_type.dart';

import 'cache_utils.dart';

/// When an incoming attachment is downloaded without asking.
enum AutoDownloadPolicy {
  /// Always, on any network.
  always,

  /// Only on Wi-Fi, so a photo does not eat the mobile data plan.
  wifi,

  /// Never automatically; the bubble offers a download button.
  never,
}

/// Decides whether an incoming attachment may be downloaded right away.
///
/// The setting exists because attachments are the only part of a chat that can
/// quietly cost money: they arrive on their own, unlike a message.
class AutoDownload {
  AutoDownload._();

  /// Attachments below this size are always fetched: a voice message or a
  /// sticker is what makes the chat readable at all.
  static const int smallAttachmentBytes = 1024 * 1024;

  /// Whether [reference] may be downloaded now.
  static Future<bool> allows(MediaReference reference) async {
    if (reference.type == MediaType.voice ||
        reference.type == MediaType.sticker ||
        reference.size <= smallAttachmentBytes) {
      return true;
    }
    switch (await CacheUtils.getAutoDownloadPolicy()) {
      case AutoDownloadPolicy.always:
        return true;
      case AutoDownloadPolicy.wifi:
        return await onWifi();
      case AutoDownloadPolicy.never:
        return false;
    }
  }

  /// Whether the device is on an unmetered network right now.
  ///
  /// Unknown reads as "not on Wi-Fi": guessing the other way spends the user's
  /// mobile data on a policy that says not to.
  static Future<bool> onWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }
}
