import 'dart:io';

import 'package:camera/camera.dart';

/// Records the round video note started by holding down the composer's camera
/// button.
///
/// The chat page owns the camera for the few seconds the finger is down, shows
/// the circle above the composer and hands the file over when it is released.
class RoundVideoRecorder {
  /// Longest note. A note is a glance, not a video message.
  static const Duration maxLength = Duration(seconds: 60);

  CameraController? _controller;
  bool _recording = false;

  CameraController? get controller => _controller;

  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Opens the front camera and starts recording. False when there is no camera
  /// or it cannot be opened (permission, busy).
  Future<bool> start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return false;
      }
      // A note is a message to a person, not a recording of the room.
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(front, ResolutionPreset.medium, enableAudio: true);
      await controller.initialize();
      _controller = controller;
      await controller.startVideoRecording();
      _recording = true;
      return true;
    } catch (_) {
      await dispose();
      return false;
    }
  }

  /// Stops and returns the recorded file, or null when nothing was recorded.
  Future<File?> stop() async {
    final controller = _controller;
    if (controller == null || !_recording) {
      await dispose();
      return null;
    }
    _recording = false;
    try {
      final captured = await controller.stopVideoRecording();
      final file = File(captured.path);
      await dispose();
      return file;
    } catch (_) {
      await dispose();
      return null;
    }
  }

  /// Stops and throws the recording away.
  Future<void> cancel() async {
    final controller = _controller;
    if (controller != null && _recording) {
      _recording = false;
      try {
        final captured = await controller.stopVideoRecording();
        await File(captured.path)
            .delete()
            .catchError((_) => File(captured.path));
      } catch (_) {
        // Nothing to keep.
      }
    }
    await dispose();
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    _recording = false;
    try {
      await controller?.dispose();
    } catch (_) {
      // The platform side may already be gone.
    }
  }
}
