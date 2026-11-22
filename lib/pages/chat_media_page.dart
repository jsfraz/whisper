import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import '../models/private_message.dart';
import '../utils/cache_utils.dart';
import '../utils/media_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/nav_transitions.dart';
import '../utils/theme_utils.dart';
import '../widgets/media_bubble.dart';
import 'media_viewer_page.dart';

/// Every attachment of one chat this device can open, newest first.
class ChatMediaPage extends StatefulWidget {
  const ChatMediaPage(this.userId, {super.key, this.chatThemeColor});

  final String userId;

  /// The chat's own color, so the grid and the viewer open in it.
  final Color? chatThemeColor;

  @override
  State<ChatMediaPage> createState() => _ChatMediaPageState();
}

class _ChatMediaPageState extends State<ChatMediaPage> {
  List<PrivateMessage> _media = [];

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    List<PrivateMessage> messages =
        await CacheUtils.getPrivateMessages(widget.userId);
    if (mounted) {
      setState(() {
        _media = MessageNotifier.viewableMedia(messages);
      });
    }
  }

  void _openMedia(PrivateMessage message) {
    final path = message.localPath;
    final type = message.mediaType;
    if (path == null || type == null) {
      return;
    }
    Navigator.of(context).push(
      fadeRoute(
        // The viewer is a separate route, so it needs the chat theme passed in
        Theme(
          data: ThemeUtils.chatTheme(context, widget.chatThemeColor),
          child: MediaViewerPage(
            message: message,
            conversationUserId: widget.userId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeUtils.chatTheme(context, widget.chatThemeColor),
      child: Scaffold(
        appBar: AppBar(
          title: Text('mediaTitle'.tr()),
        ),
        body: SafeArea(
          child: _media.isEmpty
              ? Center(
                  child: Text(
                    'noMedia'.tr(),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              // A sliver grid, so only the visible tiles decrypt.
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _media.length,
                  itemBuilder: (context, index) => _MediaTile(
                    message: _media[index],
                    onTap: () => _openMedia(_media[index]),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Square thumbnail of one shared media message.
class _MediaTile extends StatefulWidget {
  const _MediaTile({required this.message, required this.onTap});

  final PrivateMessage message;
  final VoidCallback onTap;

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    // Videos get a first-frame thumbnail; documents show an icon.
    if (widget.message.mediaType == MediaType.video ||
        widget.message.mediaType == MediaType.file) {
      return;
    }
    final path = widget.message.localPath;
    if (path == null) {
      return;
    }
    try {
      Uint8List bytes = await MediaUtils.decryptAtRest(path);
      if (mounted) {
        setState(() {
          _bytes = bytes;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
        });
      }
    }
  }

  /// One tile of the three-column grid, gaps and padding taken off.
  double get _tileWidth => (MediaQuery.sizeOf(context).width - 24) / 3;

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.message.mediaType == MediaType.video;
    final isFile = widget.message.mediaType == MediaType.file;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: isVideo
            ? _videoTile()
            : _bytes != null
                ? Image.memory(_bytes!,
                    fit: BoxFit.cover,
                    // Tile-sized decode: a full-resolution photo per square is
                    // 40+ MB of bitmap and a visible hitch while scrolling.
                    cacheWidth: MediaUtils.decodeWidth(context, _tileWidth))
                : Center(
                    child: _error
                        ? const Icon(Icons.broken_image, size: 24)
                        : isFile
                            ? _fileTile()
                            : const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                  ),
      ),
    );
  }

  /// Video: first frame with a play badge.
  Widget _videoTile() {
    return Stack(
      fit: StackFit.expand,
      children: [
        VideoThumbnail(path: widget.message.localPath),
        const Center(
          child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
        ),
      ],
    );
  }

  /// Documents: extension badge instead of a thumbnail.
  Widget _fileTile() {
    final name = widget.message.fileName ?? '';
    final dot = name.lastIndexOf('.');
    final extension =
        dot > 0 && dot < name.length - 1 ? name.substring(dot + 1) : '';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(MediaUtils.iconForFileName(widget.message.fileName), size: 24),
        if (extension.isNotEmpty)
          Text(
            extension.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }
}
