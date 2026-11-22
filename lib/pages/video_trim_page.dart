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

  /// Selection in milliseconds, as the trim viewer reports it.
  double _startValue = 0;
  double _endValue = 0;
  bool _ready = false;
  bool _playing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _trimmer.loadVideo(videoPath: widget.file.path);
    // The viewer starts on the whole clip; without this the selection would be
    // the 0..0 range it is initialised with.
    final durationMs = _trimmer
            .videoPlayerController?.value.duration.inMilliseconds
            .toDouble() ??
        0;
    if (mounted) {
      setState(() {
        _ready = true;
        _endValue = durationMs;
      });
    }
  }

  Future<void> _togglePlayback() async {
    final playing = await _trimmer.videoPlaybackControl(
      startValue: _startValue,
      endValue: _endValue,
    );
    if (mounted && playing != _playing) {
      setState(() => _playing = playing);
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

  String _format(double milliseconds) {
    final total = Duration(milliseconds: milliseconds.round());
    final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    final tenths = (total.inMilliseconds.remainder(1000) ~/ 100);
    return '$minutes:$seconds.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    final hasRange = _endValue > _startValue;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('trimVideo'.tr()),
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  // The picture gets the room: this is where the cut is judged.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: VideoViewer(
                        trimmer: _trimmer,
                        borderColor: Colors.white24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_format(_startValue),
                            style: const TextStyle(
                                color: Colors.white70,
                                fontFeatures: [FontFeature.tabularFigures()])),
                        Text(_format(_endValue - _startValue),
                            style: const TextStyle(
                                color: Color(0xFFFFC400),
                                fontWeight: FontWeight.w600)),
                        Text(_format(_endValue),
                            style: const TextStyle(
                                color: Colors.white70,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TrimViewer(
                      trimmer: _trimmer,
                      viewerWidth: MediaQuery.sizeOf(context).width - 32,
                      viewerHeight: 56,
                      showDuration: false,
                      paddingFraction: 0.15,
                      onChangeStart: (value) =>
                          setState(() => _startValue = value),
                      onChangeEnd: (value) => setState(() => _endValue = value),
                      onChangePlaybackState: (value) =>
                          setState(() => _playing = value),
                    ),
                  ),
                  IconButton(
                    iconSize: 56,
                    color: Colors.white,
                    onPressed: hasRange ? _togglePlayback : null,
                    icon: Icon(
                      _playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                _saving ? null : () => Navigator.pop(context),
                            child: Text('cancel'.tr()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: hasRange && !_saving ? _save : null,
                            icon: const Icon(Icons.content_cut),
                            label: Text('applyTrim'.tr()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
