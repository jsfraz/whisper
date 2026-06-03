import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import '../models/private_message.dart';
import '../pages/media_viewer_page.dart';
import '../utils/media_utils.dart';
import 'voice_player.dart';

/// Renders a media attachment inside a chat bubble: image/gif thumbnail, video
/// preview with a play overlay, or an inline voice player. Handles the
/// download/loading/failed states for incoming media.
class MediaBubble extends StatefulWidget {
  final PrivateMessage message;
  final Color bubbleColor;
  final Color textColor;
  final VoidCallback onRetry;
  final bool canRetry;

  const MediaBubble({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.onRetry,
    required this.canRetry,
    super.key,
  });

  @override
  State<MediaBubble> createState() => _MediaBubbleState();
}

class _MediaBubbleState extends State<MediaBubble> {
  Future<Uint8List>? _imageFuture;

  @override
  void initState() {
    super.initState();
    _prepareFutures();
  }

  @override
  void didUpdateWidget(covariant MediaBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.localPath != widget.message.localPath ||
        oldWidget.message.downloadStatus != widget.message.downloadStatus) {
      _prepareFutures();
    }
  }

  void _prepareFutures() {
    _imageFuture = null;
    final path = widget.message.localPath;
    if (path == null) {
      return;
    }
    final type = widget.message.mediaType;
    if (type == MediaType.image || type == MediaType.gif) {
      _imageFuture = MediaUtils.decryptAtRest(path);
    }
  }

  /// Constrained display size derived from the original media dimensions.
  Size _displaySize() {
    const maxW = 240.0;
    const maxH = 320.0;
    final w = widget.message.width;
    final h = widget.message.height;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return const Size(220, 220);
    }
    double dw = w.toDouble();
    double dh = h.toDouble();
    final scale = (maxW / dw).clamp(0.0, 1.0);
    dw *= scale;
    dh *= scale;
    if (dh > maxH) {
      final s = maxH / dh;
      dh *= s;
      dw *= s;
    }
    return Size(dw, dh);
  }

  void _openViewer() {
    final path = widget.message.localPath;
    final type = widget.message.mediaType;
    if (path == null || type == null) {
      return;
    }
    Navigator.of(context).push(
      PageTransition(
        type: PageTransitionType.fade,
        duration: const Duration(milliseconds: 200),
        child: MediaViewerPage(
          localPath: path,
          type: type,
          caption: widget.message.message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.message.mediaType;
    final hasCaption = widget.message.message.isNotEmpty;

    Widget media;
    if (widget.message.downloadStatus == MediaDownloadStatus.pending) {
      media = _placeholder(child: const CircularProgressIndicator());
    } else if (widget.message.downloadStatus == MediaDownloadStatus.failed) {
      media = _failed();
    } else if (widget.message.localPath == null) {
      media = _placeholder(child: const CircularProgressIndicator());
    } else {
      switch (type) {
        case MediaType.image:
        case MediaType.gif:
          media = _imageWidget();
          break;
        case MediaType.video:
          media = _videoWidget();
          break;
        case MediaType.voice:
          media = _voiceWidget();
          break;
        case null:
          media = _placeholder(child: const Icon(Icons.broken_image));
      }
    }

    final isVoice = type == MediaType.voice;
    if (isVoice) {
      // Voice messages live inside the coloured bubble.
      return Container(
        decoration: BoxDecoration(
          color: widget.bubbleColor,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: media,
      );
    }

    // Visual media: rounded thumbnail with optional caption underneath.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: media,
        ),
        if (hasCaption)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: widget.bubbleColor,
              borderRadius: BorderRadius.circular(16),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              widget.message.message,
              style: TextStyle(color: widget.textColor),
            ),
          ),
      ],
    );
  }

  Widget _placeholder({required Widget child}) {
    final size = _displaySize();
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _failed() {
    final size = _displaySize();
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 32),
          const SizedBox(height: 8),
          Text('mediaDownloadFailed'.tr(), textAlign: TextAlign.center),
          if (widget.canRetry)
            TextButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh),
              label: Text('retry'.tr()),
            ),
        ],
      ),
    );
  }

  Widget _imageWidget() {
    final size = _displaySize();
    return GestureDetector(
      onTap: _openViewer,
      child: FutureBuilder<Uint8List>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _placeholder(child: const CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return _placeholder(child: const Icon(Icons.broken_image));
          }
          return Image.memory(
            snapshot.data!,
            width: size.width,
            height: size.height,
            fit: BoxFit.cover,
          );
        },
      ),
    );
  }

  Widget _videoWidget() {
    final size = _displaySize();
    return GestureDetector(
      onTap: _openViewer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2B2B2B), Color(0xFF000000)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(8),
            child:
                const Icon(Icons.play_arrow, color: Colors.white, size: 36),
          ),
          if (widget.message.durationMs != null)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatDuration(widget.message.durationMs!),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _voiceWidget() {
    return VoicePlayer(
      localPath: widget.message.localPath!,
      durationMs: widget.message.durationMs,
      color: widget.textColor,
    );
  }

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
