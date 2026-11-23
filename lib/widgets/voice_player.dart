import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../utils/cache_utils.dart';
import '../utils/media_utils.dart';
import '../utils/playback_lock.dart';
import '../utils/playback_speed.dart';
import '../utils/voice_autoplay.dart';

/// Inline player for a voice message stored encrypted-at-rest.
///
/// The encrypted file is decrypted into a temporary plaintext file for
/// playback and deleted again on dispose.
class VoicePlayer extends StatefulWidget {
  final String localPath;
  final int? durationMs;
  final Color color;

  /// The chat this message lives in, and when it was sent: together they are
  /// the key the next-message chain looks for.
  final String conversationId;
  final DateTime sentAt;

  /// Loudness samples recorded with the message, empty for older ones.
  final List<int>? waveform;

  const VoicePlayer({
    required this.localPath,
    required this.color,
    required this.conversationId,
    required this.sentAt,
    this.durationMs,
    this.waveform,
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

  /// Set once the finished message has asked for the next one, so a repeated
  /// `completed` event does not restart the chain.
  bool _chained = false;

  late final String _key =
      CacheUtils.messageKey(widget.conversationId, widget.sentAt);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        PlaybackLock.release(this);
        if (!_chained) {
          _chained = true;
          VoiceAutoplay.next(widget.conversationId, widget.sentAt);
        }
        return;
      }
      if (!state.playing) {
        PlaybackLock.release(this);
      }
    });
    PlaybackLock.owner.addListener(_onLockChanged);
    VoiceAutoplay.request.addListener(_onAutoplayRequest);
    _prepare();
  }

  /// Starts this message when the previous one finished and asked for it.
  void _onAutoplayRequest() {
    if (VoiceAutoplay.request.value != _key) {
      return;
    }
    VoiceAutoplay.request.value = null;
    if (_loading || _error) {
      return;
    }
    PlaybackLock.claim(this);
    _player.play();
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
    VoiceAutoplay.request.removeListener(_onAutoplayRequest);
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

  /// Waveform of the message, or a plain track for a message recorded before
  /// the shape was stored. Tap or drag seeks, like the slider it replaces.
  Widget _waveformBar(BuildContext context, Duration total, Duration position) {
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        void seek(Offset local) {
          if (_loading || total.inMilliseconds == 0) {
            return;
          }
          final fraction = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
          _player.seek(Duration(
              milliseconds: (total.inMilliseconds * fraction).round()));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seek(details.localPosition),
          onHorizontalDragUpdate: (details) => seek(details.localPosition),
          child: SizedBox(
            height: 26,
            child: CustomPaint(
              painter: _WaveformPainter(
                samples: widget.waveform ?? const [],
                progress: progress,
                color: widget.color,
              ),
            ),
          ),
        );
      },
    );
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
                            _chained = false;
                            await _player.seek(Duration.zero);
                          }
                          _chained = false;
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
                // The waveform and the time label sit on one line, so the bars
                // are vertically centred in the row instead of being pushed up
                // by a stacked label.
                return StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, stateSnapshot) {
                    final completed = stateSnapshot.data?.processingState ==
                        ProcessingState.completed;
                    // The speed control appears with playback and is gone
                    // again once the message finished. It sits under the time,
                    // so the track gets an equal spacer above it to stay
                    // centred on the play button instead of drifting up.
                    final started = position > Duration.zero && !completed;
                    const double speedLine = 16;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (started) const SizedBox(height: speedLine),
                        Row(
                          children: [
                            Expanded(
                              child: _waveformBar(context, total, position),
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
                          SizedBox(
                            height: speedLine,
                            child: Align(
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

/// Draws the loudness bars of a voice message, the played part in full colour.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.color,
  });

  final List<int> samples;
  final double progress;
  final Color color;

  /// Bars drawn at most. A long recording has one sample per 100 ms, which
  /// would be sub-pixel wide: the samples are folded into this many peaks.
  static const int maxBars = 32;

  /// Folds [samples] into at most [maxBars] peaks, so a bar is always visible.
  List<int> _bars() {
    if (samples.length <= maxBars) {
      return samples;
    }
    final bucket = samples.length / maxBars;
    return List<int>.generate(maxBars, (index) {
      final start = (index * bucket).floor();
      final end =
          ((index + 1) * bucket).ceil().clamp(start + 1, samples.length);
      var peak = 0;
      for (var i = start; i < end; i++) {
        if (samples[i] > peak) {
          peak = samples[i];
        }
      }
      return peak;
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bars = _bars();
    if (bars.isEmpty) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint);
      return;
    }
    final step = size.width / bars.length;
    final barWidth = (step * 0.6).clamp(1.0, 4.0);
    final played = Paint()..color = color;
    final rest = Paint()..color = color.withValues(alpha: 0.3);
    for (var i = 0; i < bars.length; i++) {
      final height = (bars[i] / 100 * size.height).clamp(2.0, size.height);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(i * step + step / 2, size.height / 2),
          width: barWidth,
          height: height,
        ),
        const Radius.circular(1),
      );
      canvas.drawRRect(rect, i / bars.length <= progress ? played : rest);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.samples != samples;
}
