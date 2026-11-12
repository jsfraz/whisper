import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import '../models/private_message.dart';
import '../utils/cache_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/dialog_utils.dart';
import '../utils/media_utils.dart';
import '../utils/singleton.dart';
import '../utils/theme_utils.dart';
import 'home_page.dart';
import 'media_viewer_page.dart';

class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage(this.userId, {super.key});
  final int userId;

  /// Media messages with a local file that the viewer can open, newest first.
  /// Voice messages and attachments that are still downloading are left out.
  @visibleForTesting
  static List<PrivateMessage> sharedMedia(List<PrivateMessage> messages) {
    final media = messages
        .where((m) =>
            m.localPath != null &&
            m.mediaType != null &&
            m.mediaType != MediaType.voice &&
            m.downloadStatus == MediaDownloadStatus.ready)
        .toList();
    media.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return media;
  }

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
        _media = ChatInfoPage.sharedMedia(messages);
      });
    }
  }

  /// Pick a per-chat theme color
  Future<void> _pickChatTheme() async {
    Color? color = await showDialog<Color>(
        context: context,
        builder: (context) => DialogUtils.colorPickerDialog(
            context, _chatThemeColor ?? Singleton().appTheme.color));
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
      PageTransition(
        type: PageTransitionType.fade,
        duration: const Duration(milliseconds: 200),
        child: MediaViewerPage(
          message: message,
          conversationUserId: widget.userId,
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
          child: ListView(
            children: [
              // Chat theme
              TextButton(
                onPressed: _pickChatTheme,
                child: Row(
                  children: [
                    Icon(
                      Icons.palette,
                      size: 24,
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Text(
                        'chatTheme'.tr(),
                      ),
                    ),
                    if (_chatThemeColor != null)
                      Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _chatThemeColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 24,
                    ),
                  ],
                ),
              ),
              // Drop the override
              if (_chatThemeColor != null)
                TextButton(
                  onPressed: _clearChatTheme,
                  child: Row(
                    children: [
                      Icon(
                        Icons.restart_alt,
                        size: 24,
                      ),
                      Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Text(
                          'useGlobalTheme'.tr(),
                        ),
                      ),
                      SizedBox(
                        width: 24,
                      ),
                    ],
                  ),
                ),

              // Shared media
              if (_media.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'mediaTitle'.tr(),
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: 8),
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
              ],

              // Delete chat
              TextButton(
                onPressed: () async {
                  await DialogUtils.yesNoDialog(
                      context,
                      'deleteChatConfirm'.tr(),
                      'deleteChatConfirmText'.tr(), () async {
                    MessageNotifier().deleteChat(widget.userId);
                    // Redirect to home page and clear navigation stack
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const HomePage()),
                      (route) => false,
                    );
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever,
                      size: 24,
                      color: Colors.red,
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Text(
                        'deleteChat'.tr(),
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    SizedBox(
                      width: 24,
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
    // Videos have no thumbnail generator, the play icon is enough.
    if (widget.message.mediaType == MediaType.video) {
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
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: _bytes != null
            ? Image.memory(_bytes!, fit: BoxFit.cover)
            : Center(
                child: _error
                    ? Icon(Icons.broken_image, size: 24)
                    : isVideo
                        ? Icon(Icons.play_arrow, size: 32)
                        : SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
              ),
      ),
    );
  }
}
