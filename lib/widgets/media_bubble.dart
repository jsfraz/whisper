import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';
import 'package:video_player/video_player.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import '../models/private_message.dart';
import '../pages/media_viewer_page.dart';
import '../utils/media_utils.dart';
import 'voice_player.dart';

/// Renders a media attachment inside a chat bubble: image/gif thumbnail, video
/// preview with a play overlay, an inline voice player, or an album grid.
/// Handles the download/loading/failed states for incoming media.
class MediaBubble extends StatefulWidget {
  final PrivateMessage message;
  final Color bubbleColor;
  final Color textColor;
  final VoidCallback onRetry;
  final bool canRetry;
  final String conversationUserId;

  const MediaBubble({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.onRetry,
    required this.canRetry,
    required this.conversationUserId,
    super.key,
  });

  @override
  State<MediaBubble> createState() => _MediaBubbleState();
}

class _MediaBubbleState extends State<MediaBubble> {
  Future<Uint8List>? _imageFuture;

  /// Path the current [_imageFuture] belongs to. The cache mutates the same
  /// message instance in place, so comparing widget objects cannot detect a
  /// finished download; the path can.
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _prepareImage();
  }

  @override
  void didUpdateWidget(covariant MediaBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepareImage();
  }

  void _prepareImage() {
    final path = widget.message.localPath;
    if (path == _imagePath) {
      return;
    }
    _imagePath = path;
    final type = widget.message.mediaType;
    final isImage = type == MediaType.image || type == MediaType.gif;
    _imageFuture =
        path != null && isImage ? MediaUtils.decryptAtRest(path) : null;
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

  void _openViewer({int albumIndex = 0}) {
    final path = widget.message.localPath;
    final type = widget.message.mediaType;
    if (!widget.message.isAlbum && (path == null || type == null)) {
      return;
    }
    Navigator.of(context).push(
      PageTransition(
        type: PageTransitionType.fade,
        duration: const Duration(milliseconds: 200),
        // The viewer is a separate route; carry the chat theme over to it
        child: Theme(
          data: Theme.of(context),
          child: MediaViewerPage(
            message: widget.message,
            conversationUserId: widget.conversationUserId,
            albumIndex: albumIndex,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.message.mediaType;
    final hasCaption = widget.message.message.isNotEmpty;

    if (widget.message.isAlbum) {
      return _albumWidget(hasCaption);
    }

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
        case MediaType.file:
          media = _fileWidget();
          break;
        case null:
          media = _placeholder(child: const Icon(Icons.broken_image));
      }
    }

    // Voice and file messages live inside the coloured bubble.
    final insideBubble = type == MediaType.voice || type == MediaType.file;
    if (insideBubble) {
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
    return _withCaption(media, hasCaption);
  }

  /// Album: two-column grid of thumbnails (four tiles max, the last one shows
  /// how many are hidden) plus the shared caption.
  Widget _albumWidget(bool hasCaption) {
    final items = widget.message.album;
    const tile = 110.0;
    const gap = 4.0;
    final shown = items.length > 4 ? 4 : items.length;
    return _withCaption(
      SizedBox(
        width: tile * 2 + gap,
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
          ),
          itemCount: shown,
          itemBuilder: (context, index) {
            final hidden = items.length > 4 && index == 3
                ? items.length - 3
                : null;
            return AlbumTile(
              item: items[index],
              hiddenCount: hidden,
              onTap: () => _openViewer(albumIndex: index),
            );
          },
        ),
      ),
      hasCaption,
    );
  }

  Widget _withCaption(Widget media, bool hasCaption) {
    return Column(
      // Own messages sit on the right, so the caption does too.
      crossAxisAlignment: widget.message.isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            VideoThumbnail(path: widget.message.localPath),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            // Center gives the badge its intrinsic size; without it the
            // StackFit.expand stack stretches the circle over the whole bubble.
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(3),
                child:
                    const Icon(Icons.play_arrow, color: Colors.white, size: 18),
              ),
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

  /// Document bubble: icon, file name and size; opens the viewer's file page.
  Widget _fileWidget() {
    final name = widget.message.fileName ?? 'mediaFile'.tr();
    return GestureDetector(
      onTap: _openViewer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(MediaUtils.iconForFileName(widget.message.fileName),
                color: widget.textColor, size: 32),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: widget.textColor),
                  ),
                  if (widget.message.mediaSize != null)
                    Text(
                      MediaUtils.formatBytes(widget.message.mediaSize!),
                      style: TextStyle(
                        color: widget.textColor.withValues(alpha: 0.7),
                        fontSize: 11,
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

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// One tile of an album bubble: image/gif thumbnail, first video frame, or a
/// type icon, with its own download state.
class AlbumTile extends StatefulWidget {
  final AlbumItem item;

  /// When set, this tile stands in for all remaining attachments.
  final int? hiddenCount;
  final VoidCallback onTap;

  const AlbumTile({
    required this.item,
    required this.onTap,
    this.hiddenCount,
    super.key,
  });

  @override
  State<AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<AlbumTile> {
  Future<Uint8List>? _imageFuture;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant AlbumTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepare();
  }

  void _prepare() {
    final path = widget.item.localPath;
    if (path == _imagePath) {
      return;
    }
    _imagePath = path;
    final type = widget.item.mediaType;
    final isImage = type == MediaType.image || type == MediaType.gif;
    _imageFuture =
        path != null && isImage ? MediaUtils.decryptAtRest(path) : null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final type = item.mediaType;
    Widget content;
    if (widget.hiddenCount != null &&
        widget.hiddenCount! > 0 &&
        item.isReady) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          _thumbnail(type),
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            alignment: Alignment.center,
            child: Text(
              '+${widget.hiddenCount}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    } else if (item.status == MediaDownloadStatus.failed) {
      content = const Center(child: Icon(Icons.error_outline));
    } else if (!item.isReady) {
      content =
          const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      content = _thumbnail(type);
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.black.withValues(alpha: 0.1),
          child: content,
        ),
      ),
    );
  }

  Widget _thumbnail(MediaType? type) {
    switch (type) {
      case MediaType.image:
      case MediaType.gif:
        return FutureBuilder<Uint8List>(
          future: _imageFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snapshot.hasData) {
              return const Center(child: Icon(Icons.broken_image));
            }
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          },
        );
      case MediaType.video:
        return Stack(
          fit: StackFit.expand,
          children: [
            VideoThumbnail(path: widget.item.localPath),
            const Center(
                child: Icon(Icons.play_circle_outline,
                    color: Colors.white, size: 20)),
          ],
        );
      case MediaType.voice:
        return const Center(child: Icon(Icons.mic));
      case MediaType.file:
        return Center(
            child: Icon(MediaUtils.iconForFileName(widget.item.fileName)));
      case null:
        return const Center(child: Icon(Icons.broken_image));
    }
  }
}

/// First frame of an encrypted-at-rest video, used as a bubble thumbnail.
/// Materializes a temporary plaintext file for the platform player and
/// releases both when the bubble is disposed.
class VideoThumbnail extends StatefulWidget {
  final String? path;

  const VideoThumbnail({this.path, super.key});

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _controller;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _disposeController();
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == null) {
      return;
    }
    try {
      final temp = await MediaUtils.materializeTempFile(
          path, MediaUtils.extensionForType(MediaType.video));
      final controller = VideoPlayerController.file(temp);
      await controller.initialize();
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        MediaUtils.deleteLocalFile(temp.path);
        return;
      }
      setState(() {
        _tempFile = temp;
        _controller = controller;
      });
    } catch (_) {
      // The gradient fallback stays visible.
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    final temp = _tempFile;
    _tempFile = null;
    if (temp != null) {
      MediaUtils.deleteLocalFile(temp.path);
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B2B2B), Color(0xFF000000)],
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
