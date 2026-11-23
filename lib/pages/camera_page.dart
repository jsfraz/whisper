import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // The camera is the one screen that follows the phone: a photo taken on a
    // turned phone is a landscape photo. Everything else stays portrait.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
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
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            _preview(controller)
          else
            const Center(child: CircularProgressIndicator()),
          SafeArea(
            child: portrait
                ? Column(
                    children: [
                      _topBar(showTimer: true),
                      const Spacer(),
                      _shutter(),
                      const SizedBox(height: 40),
                    ],
                  )
                // Turned to the side, the shutter moves to the right edge where
                // the thumb rests, the way the system camera does it.
                : Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: _topBar(showTimer: false),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_recording) _timerChip(),
                              _shutter(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBar({required bool showTimer}) {
    return Row(
      children: [
        IconButton(
          color: Colors.white,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        const Spacer(),
        if (showTimer && _recording) _timerChip(),
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
    );
  }

  Widget _timerChip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 6),
          Text(
            '${_format(_elapsed)} / ${_format(CameraPage.maxVideoLength)}',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// The sensor reports a landscape frame; on a turned phone the sides swap, so
  /// the fill has to cover the screen instead of sitting in a letterboxed band.
  Widget _preview(CameraController controller) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final aspect = controller.value.aspectRatio;
    final width = portrait ? 1 / aspect : aspect;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width * 1000,
          height: 1000,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  /// Tap takes a photo, holding records a video until it is released.
  Widget _shutter() {
    return GestureDetector(
      onTap: _takePhoto,
      onLongPressStart: (_) => _startVideo(),
      onLongPressEnd: (_) => _stopVideo(),
      child: _shutterButton(),
    );
  }

  Widget _shutterButton() {
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
