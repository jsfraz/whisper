import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/nav_transitions.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import '../models/private_message.dart';
import '../utils/cache_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/dialog_utils.dart';
import '../utils/media_utils.dart';
import '../utils/singleton.dart';
import '../utils/theme_utils.dart';
import '../widgets/media_bubble.dart';
import '../widgets/settings_tile.dart';
import 'home_page.dart';
import 'media_viewer_page.dart';

class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage(this.userId, {super.key});
  final String userId;

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  Color? _chatThemeColor;
  List<PrivateMessage> _media = [];

  @override
  void initState() {
    super.initState();
    _loadChatTheme();
    _loadMedia();
  }

  Future<void> _loadChatTheme() async {
    Color? color = await CacheUtils.getChatTheme(widget.userId);
    if (mounted) {
      setState(() {
        _chatThemeColor = color;
      });
    }
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

  /// Pick a per-chat theme color. The dialog uses the chat color too.
  Future<void> _pickChatTheme() async {
    Color? color = await showDialog<Color>(
        context: context,
        builder: (dialogContext) => Theme(
              data: ThemeUtils.chatTheme(context, _chatThemeColor),
              child: Builder(
                builder: (themedContext) => DialogUtils.colorPickerDialog(
                    themedContext,
                    _chatThemeColor ?? Singleton().appTheme.color),
              ),
            ));
    if (color == null || !mounted) {
      return;
    }
    await CacheUtils.setChatTheme(widget.userId, color);
    await _loadChatTheme();
  }

  /// Drop the per-chat theme and fall back to the global one
  Future<void> _clearChatTheme() async {
    await CacheUtils.clearChatTheme(widget.userId);
    await _loadChatTheme();
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
          data: ThemeUtils.chatTheme(context, _chatThemeColor),
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
      data: ThemeUtils.chatTheme(context, _chatThemeColor),
      child: Scaffold(
        appBar: AppBar(
          title: Text('chatInfoPage'.tr()),
        ),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // Chat theme
                    SettingsTile(
                      icon: Icons.palette,
                      label: 'chatTheme'.tr(),
                      onPressed: _pickChatTheme,
                      extra: _chatThemeColor == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: _chatThemeColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                    ),
                    // Drop the override
                    if (_chatThemeColor != null)
                      SettingsTile(
                        icon: Icons.restart_alt,
                        label: 'useGlobalTheme'.tr(),
                        onPressed: _clearChatTheme,
                      ),

                    Divider(thickness: 1, indent: 10, endIndent: 10),
                  ],
                ),
              ),

              // Shared media title
              if (_media.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'mediaTitle'.tr(),
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              // Grid as a sliver, so only the visible tiles decrypt
              if (_media.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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

              SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (_media.isNotEmpty)
                      Divider(thickness: 1, indent: 10, endIndent: 10),

                    // Delete chat
                    SettingsTile(
                      icon: Icons.delete_forever,
                      label: 'deleteChat'.tr(),
                      color: Colors.red,
                      onPressed: () async {
                        await DialogUtils.yesNoDialog(
                            context,
                            'deleteChatConfirm'.tr(),
                            'deleteChatConfirmText'.tr(), () async {
                          MessageNotifier().deleteChat(widget.userId);
                          // Redirect to home page and clear navigation stack
                          Navigator.pushAndRemoveUntil(
                            context,
                            fadeRoute(const HomePage()),
                            (route) => false,
                          );
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
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
                ? Image.memory(_bytes!, fit: BoxFit.cover)
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
