import 'dart:io';
import 'dart:typed_data';

import 'package:chewie/chewie.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import '../models/private_message.dart';
import '../utils/cache_utils.dart';
import '../utils/media_utils.dart';
import '../utils/message_actions.dart';
import '../utils/message_notifier.dart';

/// Fullscreen viewer for the media of one conversation, stored
/// encrypted-at-rest. Swiping moves between the attachments.
class MediaViewerPage extends StatefulWidget {
  final PrivateMessage message;

  /// The other side of the conversation: the source of the other attachments
  /// and what the delete action needs.
  final int conversationUserId;

  const MediaViewerPage({
    required this.message,
    required this.conversationUserId,
    super.key,
  });

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  List<PrivateMessage> _media = [];
  PageController? _controller;
  int _index = 0;

  PrivateMessage get _current => _media[_index];

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  /// The viewer pages through the same attachments the gallery shows, starting
  /// at the one that was tapped.
  Future<void> _loadMedia() async {
    final messages =
        await CacheUtils.getPrivateMessages(widget.conversationUserId);
    final media = MessageNotifier.viewableMedia(messages);
    final index = media.indexWhere((m) =>
        m.senderId == widget.message.senderId &&
        m.sentAt == widget.message.sentAt);
    if (!mounted) {
      return;
    }
    setState(() {
      _media = media.isEmpty ? [widget.message] : media;
      _index = index < 0 ? 0 : index;
      _controller = PageController(initialPage: _index);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Overflow menu of the viewer: the same actions as the bubble sheet, except
  /// copy (the caption is already visible).
  PopupMenuButton<String> _buildActions() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'save':
            MessageActions.save(_current);
            break;
          case 'forward':
            MessageActions.forward(context, _current);
            break;
          case 'delete':
            MessageActions.delete(context, _current, widget.conversationUserId,
                onDeleted: () => Navigator.pop(context));
            break;
        }
      },
      itemBuilder: (context) => [
        if (MessageActions.canSave(_current))
          _menuItem('save', MessageActions.saveIcon, 'saveAttachment'.tr()),
        _menuItem('forward', MessageActions.forwardIcon, 'forwardMessage'.tr()),
        _menuItem(
            'delete', MessageActions.deleteIcon, 'deleteMessageForMe'.tr()),
      ],
    );
  }

  /// Menu row with the same icon the bubble sheet uses for this action.
  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final caption = controller == null ? '' : _current.message;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        actions: controller == null ? null : [_buildActions()],
      ),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: controller,
              itemCount: _media.length,
              onPageChanged: (index) => setState(() {
                _index = index;
              }),
              itemBuilder: (context, index) => Center(
                child: _MediaPage(_media[index]),
              ),
            ),
      bottomNavigationBar: caption.isNotEmpty
          ? Container(
              color: colors.surface,
              padding: const EdgeInsets.all(16),
              child: SafeArea(
                top: false,
                child: Text(
                  caption,
                  style: TextStyle(color: colors.onSurface),
                ),
              ),
            )
          : null,
    );
  }
}

/// One attachment of the viewer: decodes its own file and releases it again
/// when the page is swiped away.
class _MediaPage extends StatefulWidget {
  const _MediaPage(this.message);
  final PrivateMessage message;

  @override
  State<_MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<_MediaPage> {
  Uint8List? _imageBytes;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _tempFile;
  bool _loading = true;
  bool _error = false;

  MediaType get _type => widget.message.mediaType ?? MediaType.image;

  bool get _isVideo => _type == MediaType.video;

  bool get _isFile => _type == MediaType.file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final localPath = widget.message.localPath;
      if (localPath == null) {
        throw Exception('no local media');
      }
      if (_isFile) {
        // A file shows its icon and metadata, never its content.
      } else if (_isVideo) {
        _tempFile = await MediaUtils.materializeTempFile(
            localPath, MediaUtils.extensionForType(_type));
        final controller = VideoPlayerController.file(_tempFile!);
        await controller.initialize();
        _videoController = controller;
        _chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
        );
      } else {
        _imageBytes = await MediaUtils.decryptAtRest(localPath);
      }
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
    _chewieController?.dispose();
    _videoController?.dispose();
    MediaUtils.deleteLocalFile(_tempFile?.path);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const CircularProgressIndicator();
    }
    if (_error) {
      return Text('mediaError'.tr(),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface));
    }
    if (_isFile) {
      return _filePage();
    }
    if (_isVideo && _chewieController != null) {
      return AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Chewie(controller: _chewieController!),
      );
    }
    if (_imageBytes != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: SizedBox.expand(
          child: Image.memory(_imageBytes!, fit: BoxFit.contain),
        ),
      );
    }
    return Text('mediaError'.tr(),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface));
  }

  /// File page: icon, name, size and a save button.
  Widget _filePage() {
    final message = widget.message;
    final name = message.fileName ?? 'mediaFile'.tr();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(MediaUtils.iconForFileName(message.fileName),
              color: colors.onSurface, size: 64),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurface, fontSize: 16),
          ),
          if (message.mediaSize != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                MediaUtils.formatBytes(message.mediaSize!),
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => MessageActions.save(message),
            icon: const Icon(Icons.download),
            label: Text('saveAttachment'.tr()),
          ),
        ],
      ),
    );
  }
}
