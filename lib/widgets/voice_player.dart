import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../utils/cache_utils.dart';
import '../utils/media_utils.dart';
import '../utils/playback_lock.dart';
import '../utils/playback_speed.dart';

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

class _VoicePlayerState extends State<VoicePlayer> with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  File? _tempFile;
  bool _loading = true;
  bool _error = false;
  double _speed = playbackSpeeds.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.playerStateStream.listen((state) {
      if (!state.playing ||
          state.processingState == ProcessingState.completed) {
        PlaybackLock.release(this);
      }
    });
    PlaybackLock.owner.addListener(_onLockChanged);
    _prepare();
  }

  /// Pauses when another voice message or a video starts playing.
  void _onLockChanged() {
    if (!identical(PlaybackLock.owner.value, this) && _player.playing) {
      _player.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _player.pause();
    }
  }

  Future<void> _prepare() async {
    try {
      _tempFile =
          await MediaUtils.materializeTempFile(widget.localPath, '.m4a');
      await _player.setFilePath(_tempFile!.path);
      _speed = await CacheUtils.getPlaybackSpeed();
      await _player.setSpeed(_speed);
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
    WidgetsBinding.instance.removeObserver(this);
    PlaybackLock.owner.removeListener(_onLockChanged);
    PlaybackLock.release(this);
    _player.dispose();
    MediaUtils.deleteLocalFile(_tempFile?.path);
    super.dispose();
  }

  /// Steps to the next speed and stores it for every other message.
  Future<void> _cycleSpeed() async {
    final speed = nextSpeed(_speed);
    setState(() {
      _speed = speed;
    });
    await _player.setSpeed(speed);
    await CacheUtils.setPlaybackSpeed(speed);
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
                          PlaybackLock.claim(this);
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
                // Slider and the time label sit on one line, so the track is
                // vertically centred in the row instead of being pushed up by
                // a stacked label.
                return StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, stateSnapshot) {
                    final completed = stateSnapshot.data?.processingState ==
                        ProcessingState.completed;
                    // The speed control appears with playback and is gone
                    // again once the message finished.
                    final started = position > Duration.zero && !completed;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 12),
                                  activeTrackColor: widget.color,
                                  thumbColor: widget.color,
                                  inactiveTrackColor:
                                      widget.color.withValues(alpha: 0.3),
                                ),
                                child: Slider(
                                  min: 0,
                                  max: max,
                                  value: value,
                                  onChanged: _loading
                                      ? null
                                      : (v) => _player.seek(
                                          Duration(milliseconds: v.toInt())),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _format(position.inMilliseconds > 0
                                  ? position
                                  : total),
                              style:
                                  TextStyle(fontSize: 11, color: widget.color),
                            ),
                          ],
                        ),
                        if (started)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Semantics(
                              button: true,
                              child: InkWell(
                                onTap: _cycleSpeed,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    speedLabel(_speed),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: widget.color,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
