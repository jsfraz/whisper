import 'dart:io';
import 'dart:typed_data';

import 'package:chewie/chewie.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import '../models/private_message.dart';
import '../utils/media_utils.dart';
import '../utils/message_actions.dart';

/// Fullscreen viewer for an image/gif or video stored encrypted-at-rest.
class MediaViewerPage extends StatefulWidget {
  final PrivateMessage message;

  /// The other side of the conversation (needed by the delete action).
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
  Uint8List? _imageBytes;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _tempFile;
  bool _loading = true;
  bool _error = false;

  MediaType get _type => widget.message.mediaType ?? MediaType.image;

  bool get _isVideo => _type == MediaType.video;

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
      if (_isVideo) {
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

  /// Overflow menu of the viewer: the same actions as the bubble sheet, except
  /// copy (the caption is already visible).
  PopupMenuButton<String> _buildActions() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'save':
            MessageActions.save(widget.message);
            break;
          case 'forward':
            MessageActions.forward(context, widget.message);
            break;
          case 'delete':
            MessageActions.delete(
                context, widget.message, widget.conversationUserId,
                onDeleted: () => Navigator.pop(context));
            break;
        }
      },
      itemBuilder: (context) => [
        if (MessageActions.canSave(widget.message))
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
    final caption = widget.message.message;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [_buildActions()],
      ),
      body: Center(
        child: _buildBody(),
      ),
      bottomNavigationBar: caption.isNotEmpty
          ? Container(
              color: Colors.black,
              padding: const EdgeInsets.all(16),
              child: SafeArea(
                top: false,
                child: Text(
                  caption,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const CircularProgressIndicator();
    }
    if (_error) {
      return Text('mediaError'.tr(),
          style: const TextStyle(color: Colors.white));
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
    return Text('mediaError'.tr(), style: const TextStyle(color: Colors.white));
  }
}
