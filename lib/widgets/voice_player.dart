import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../utils/media_utils.dart';

/// Inline player for a voice message stored encrypted-at-rest.
///
/// The encrypted file is decrypted into a temporary plaintext file for
/// playback and deleted again on dispose.
class VoicePlayer extends StatefulWidget {
  final String localPath;
  final int? durationMs;
  final Color color;

  const VoicePlayer({
    required this.localPath,
    required this.color,
    this.durationMs,
    super.key,
  });

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final AudioPlayer _player = AudioPlayer();
  File? _tempFile;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      _tempFile = await MediaUtils.materializeTempFile(widget.localPath, '.m4a');
      await _player.setFilePath(_tempFile!.path);
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    MediaUtils.deleteLocalFile(_tempFile?.path);
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: widget.color),
          const SizedBox(width: 8),
          Text('mediaError'.tr(), style: TextStyle(color: widget.color)),
        ],
      );
    }

    final total = _player.duration ??
        (widget.durationMs != null
            ? Duration(milliseconds: widget.durationMs!)
            : Duration.zero);

    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _loading
              ? SizedBox(
                  width: 36,
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.color,
                    ),
                  ),
                )
              : StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    final completed = snapshot.data?.processingState ==
                        ProcessingState.completed;
                    return IconButton(
                      color: widget.color,
                      icon: Icon((playing && !completed)
                          ? Icons.pause
                          : Icons.play_arrow),
                      onPressed: () async {
                        if (playing && !completed) {
                          await _player.pause();
                        } else {
                          if (completed) {
                            await _player.seek(Duration.zero);
                          }
                          await _player.play();
                        }
                      },
                    );
                  },
                ),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final max = total.inMilliseconds == 0
                    ? 1.0
                    : total.inMilliseconds.toDouble();
                final value =
                    position.inMilliseconds.clamp(0, max.toInt()).toDouble();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12),
                        activeTrackColor: widget.color,
                        thumbColor: widget.color,
                        inactiveTrackColor: widget.color.withValues(alpha: 0.3),
                      ),
                      child: Slider(
                        min: 0,
                        max: max,
                        value: value,
                        onChanged: _loading
                            ? null
                            : (v) => _player
                                .seek(Duration(milliseconds: v.toInt())),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _format(position.inMilliseconds > 0 ? position : total),
                        style: TextStyle(fontSize: 11, color: widget.color),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
