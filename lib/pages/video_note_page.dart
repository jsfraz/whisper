import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Records a round video note.
///
/// The picture is drawn inside a circle here and on the recipient side; the
/// file is an ordinary mp4, so nothing about playback needs a new format.
class VideoNotePage extends StatefulWidget {
  const VideoNotePage({super.key});

  /// Longest video note, seconds. A note is a glance, not a video message.
  static const Duration maxLength = Duration(seconds: 60);

  /// Opens the recorder and returns the recorded file, or null.
  static Future<File?> open(BuildContext context) {
    return Navigator.push<File>(
        context, MaterialPageRoute(builder: (_) => const VideoNotePage()));
  }

  @override
  State<VideoNotePage> createState() => _VideoNotePageState();
}

class _VideoNotePageState extends State<VideoNotePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('noCamera', 'no camera on this device');
      }
      // The front camera is what a video note is for: it is a message to a
      // person, not a recording of the room.
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(front, ResolutionPreset.medium, enableAudio: true);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (e) {
      if (mounted) {
        await Fluttertoast.showToast(
            msg: 'cameraUnavailable'.tr(), backgroundColor: Colors.red);
        Navigator.pop(context);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The plugin does not park the camera by itself: leaving it running while
    // the app is in the background keeps the camera light on.
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed) {
      _openCamera();
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !_ready) {
      return;
    }
    if (_recording) {
      await _stop();
      return;
    }
    try {
      await controller.startVideoRecording();
    } catch (_) {
      return;
    }
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        return;
      }
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= VideoNotePage.maxLength) {
        _stop();
      }
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    if (controller == null || !_recording) {
      return;
    }
    setState(() => _recording = false);
    try {
      final file = await controller.stopVideoRecording();
      if (mounted) {
        Navigator.pop(context, File(file.path));
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('videoNote'.tr()),
      ),
      body: Center(
        child: !_ready || controller == null
            ? const CircularProgressIndicator()
            : ClipOval(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller.value.previewSize?.height ?? 280,
                      height: controller.value.previewSize?.width ?? 280,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_recording)
            Text(
              '${_elapsed.inSeconds}s / ${VideoNotePage.maxLength.inSeconds}s',
              style: const TextStyle(color: Colors.white),
            ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _ready ? _toggleRecording : null,
            backgroundColor: _recording ? Colors.red : Colors.white,
            child: Icon(_recording ? Icons.stop : Icons.videocam,
                color: _recording ? Colors.white : Colors.black),
          ),
        ],
      ),
    );
  }
}
