import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

/// Picks the part of a video that is worth sending.
///
/// The platform encoder does the cut (Media3 on Android), so the output is a
/// plain mp4 that every recipient can play. Returns the trimmed file from
/// [open], or null when the user backs out.
class VideoTrimPage extends StatefulWidget {
  const VideoTrimPage(this.file, {super.key});

  final File file;

  static Future<File?> open(BuildContext context, File file) {
    return Navigator.push<File>(
        context, MaterialPageRoute(builder: (_) => VideoTrimPage(file)));
  }

  @override
  State<VideoTrimPage> createState() => _VideoTrimPageState();
}

class _VideoTrimPageState extends State<VideoTrimPage> {
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0;
  double _endValue = 1;
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _trimmer.loadVideo(videoPath: widget.file.path);
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      onSave: (path) {
        if (!mounted) {
          return;
        }
        Navigator.pop(context, path == null ? null : File(path));
      },
    );
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('trimVideo'.tr()),
        actions: [
          IconButton(
            tooltip: 'save'.tr(),
            onPressed: _ready && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle),
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: TrimViewer(
                  trimmer: _trimmer,
                  viewerWidth: MediaQuery.sizeOf(context).width,
                  viewerHeight: 240,
                  onChangeStart: (value) => _startValue = value,
                  onChangeEnd: (value) => _endValue = value,
                ),
              ),
            ),
    );
  }
}
