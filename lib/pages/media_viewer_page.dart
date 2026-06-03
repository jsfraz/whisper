import 'dart:io';
import 'dart:typed_data';

import 'package:chewie/chewie.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import '../utils/media_utils.dart';

/// Fullscreen viewer for an image/gif or video stored encrypted-at-rest.
class MediaViewerPage extends StatefulWidget {
  final String localPath;
  final MediaType type;
  final String? caption;

  const MediaViewerPage({
    required this.localPath,
    required this.type,
    this.caption,
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

  bool get _isVideo => widget.type == MediaType.video;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_isVideo) {
        _tempFile = await MediaUtils.materializeTempFile(
            widget.localPath, MediaUtils.extensionForType(widget.type));
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
        _imageBytes = await MediaUtils.decryptAtRest(widget.localPath);
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _buildBody(),
      ),
      bottomNavigationBar:
          (widget.caption != null && widget.caption!.isNotEmpty)
              ? Container(
                  color: Colors.black,
                  padding: const EdgeInsets.all(16),
                  child: SafeArea(
                    top: false,
                    child: Text(
                      widget.caption!,
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
        child: Image.memory(_imageBytes!, fit: BoxFit.contain),
      );
    }
    return Text('mediaError'.tr(), style: const TextStyle(color: Colors.white));
  }
}
