import 'dart:io';

class Utils {
  /// Check if device has Android/iOS/Fuchsia.
  static bool isPhone() {
    return Platform.isAndroid || Platform.isIOS || Platform.isFuchsia;
  }

  /// Capitalize first letter of string.
  static String capitalizeFirstLetter(String input) {
    if (input.isEmpty) {
      return input;
    }
    return input[0].toUpperCase() + input.substring(1);
  }
}
