import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The platform half of screenshot handling: blocking the screen of a view-once
/// attachment and reporting screenshots taken elsewhere. Android is the only
/// target where the block is enforceable, so on every other platform both calls
/// are a no-op.
class ScreenGuard {
  static const MethodChannel _channel = MethodChannel('whisper/secure_screen');

  /// Called when the platform noticed a screenshot.
  static VoidCallback? onScreenshot;

  /// Wires the native callback once, at startup.
  static Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        onScreenshot?.call();
      }
      return null;
    });
  }

  /// Makes the current window invisible to screenshots and recordings.
  static Future<void> enableSecure() async {
    await _invoke('enableSecure');
  }

  /// Gives the screen back once the secure view is gone.
  static Future<void> disableSecure() async {
    await _invoke('disableSecure');
  }

  static Future<void> _invoke(String method) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod(method);
    } on MissingPluginException {
      // A build without the native side still runs; it just cannot block.
    } on PlatformException {
      // Nothing to do: the block is a best effort on the platform side.
    }
  }
}
