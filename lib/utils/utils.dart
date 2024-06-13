import 'dart:io';

class Utils {
  /// Check if device has Android/iOS/Fuchsia.
  static bool isPhone() {
    return Platform.isAndroid || Platform.isIOS || Platform.isFuchsia;
  }
}
