import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// In-app camera: tap the shutter for a photo, hold it to record a video.
///
/// Returns the captured file from [open], or null when the user backs out. The
/// caller detects whether it is a photo or a video, so the chat handles it like
/// any other attachment.
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  /// Longest clip the shutter records, same as the picker used to allow.
  static const Duration maxVideoLength = Duration(seconds: 60);

  static Future<File?> open(BuildContext context) {
    return Navigator.push<File>(
        context,
        MaterialPageRoute(
            builder: (_) => const CameraPage(), fullscreenDialog: true));
  }

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  bool _flashOn = false;
  bool _recording = false;
  bool _busy = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
  }

  Future<void> _openCamera({bool front = false}) async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        throw CameraException('noCamera', 'no camera on this device');
      }
      // Whatever the caller asked for, falling back to the first camera keeps a
      // single-camera device usable.
      final wanted =
          front ? CameraLensDirection.front : CameraLensDirection.back;
      final camera = _cameras.firstWhere(
        (entry) => entry.lensDirection == wanted,
        orElse: () => _cameras.first,
      );
      final controller =
          CameraController(camera, ResolutionPreset.high, enableAudio: true);
      await controller.initialize();
      await controller.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) {
        await Fluttertoast.showToast(
            msg: 'cameraUnavailable'.tr(), backgroundColor: Colors.red);
        Navigator.pop(context);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The plugin does not park the camera by itself: left running in the
    // background it keeps the camera light on and the next open fails.
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      setState(() => _controller = null);
    } else if (state == AppLifecycleState.resumed) {
      _openCamera(front: false);
    }
  }

  Future<void> _switchCamera() async {
    if (_recording || _busy) {
      return;
    }
    final front = _cameras.isNotEmpty &&
        _controller?.description.lensDirection == CameraLensDirection.front;
    await _controller?.dispose();
    setState(() => _controller = null);
    await _openCamera(front: !front);
  }

  Future<void> _toggleFlash() async {
    if (_recording) {
      return;
    }
    final on = !_flashOn;
    try {
      await _controller?.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      return;
    }
    if (mounted) {
      setState(() => _flashOn = on);
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || _busy || _recording) {
      return;
    }
    setState(() => _busy = true);
    try {
      final captured = await controller.takePicture();
      if (mounted) {
        Navigator.pop(context, File(captured.path));
      }
    } catch (_) {
      if (mounted) {
        await Fluttertoast.showToast(
            msg: 'captureFailed'.tr(), backgroundColor: Colors.red);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _startVideo() async {
    final controller = _controller;
    if (controller == null || _busy || _recording) {
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
      if (_elapsed >= CameraPage.maxVideoLength) {
        _stopVideo();
      }
    });
  }

  Future<void> _stopVideo() async {
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    if (controller == null || !_recording) {
      return;
    }
    setState(() => _recording = false);
    try {
      final captured = await controller.stopVideoRecording();
      if (mounted) {
        Navigator.pop(context, File(captured.path));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
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

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: CameraPreview(controller),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                    const Spacer(),
                    if (_recording)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.fiber_manual_record,
                                color: Colors.red, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              '${_format(_elapsed)} / ${_format(CameraPage.maxVideoLength)}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    IconButton(
                      color: _flashOn ? Colors.amber : Colors.white,
                      onPressed: _toggleFlash,
                      icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
                    ),
                    IconButton(
                      color: Colors.white,
                      onPressed: _switchCamera,
                      icon: const Icon(Icons.cameraswitch),
                    ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: GestureDetector(
                    onTap: _takePhoto,
                    onLongPressStart: (_) => _startVideo(),
                    onLongPressEnd: (_) => _stopVideo(),
                    child: _shutter(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'shutterHint'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shutter() {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      padding: const EdgeInsets.all(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: _recording ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: _recording ? BorderRadius.circular(6) : null,
          color: _recording ? Colors.red : Colors.white,
        ),
        child: _busy
            ? const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : null,
      ),
    );
  }
}
