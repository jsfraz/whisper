import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../utils/nav_transitions.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import '../models/private_message.dart';
import '../utils/cache_utils.dart';
import '../utils/message_actions.dart';
import '../utils/message_notifier.dart';
import '../utils/dialog_utils.dart';
import '../utils/media_utils.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import '../utils/theme_utils.dart';
import '../widgets/media_bubble.dart';
import '../widgets/settings_tile.dart';
import 'home_page.dart';
import 'media_viewer_page.dart';
import 'search_page.dart';

class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage(this.userId, {super.key});
  final String userId;

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  Color? _chatThemeColor;
  List<PrivateMessage> _media = [];
  Map<String, DateTime> _pins = {};
  bool _readReceipts = false;

  /// A toggle in flight: the switch stays disabled until the server call and
  /// the cache write are done, so it cannot be flipped back and forth.
  bool _readReceiptsBusy = false;

  @override
  void initState() {
    super.initState();
    _loadChatTheme();
    _loadMedia();
    _loadPins();
    _loadReadReceipts();
  }

  Future<void> _loadReadReceipts() async {
    final enabled = await CacheUtils.isReadReceiptsEnabled(widget.userId);
    if (mounted) {
      setState(() {
        _readReceipts = enabled;
      });
    }
  }

  /// Turns receipts of this chat on or off. Turning them on publishes the
  /// current cursor right away, so the peer's ticks catch up without waiting
  /// for the next message.
  Future<void> _toggleReadReceipts(bool enabled) async {
    if (_readReceiptsBusy) {
      return;
    }
    setState(() {
      _readReceiptsBusy = true;
      _readReceipts = enabled;
    });
    try {
      await CacheUtils.setReadReceiptsEnabled(widget.userId, enabled);
      if (enabled) {
        final messages = await CacheUtils.getPrivateMessages(widget.userId);
        if (messages.isNotEmpty) {
          await Utils.sendReadCursor(widget.userId, messages.last.sentAt);
        }
      }
      await _loadReadReceipts();
    } finally {
      if (mounted) {
        setState(() => _readReceiptsBusy = false);
      }
    }
  }

  Future<void> _loadPins() async {
    final pins = await CacheUtils.getPinnedMessages(widget.userId);
    if (mounted) {
      setState(() {
        _pins = pins;
      });
    }
  }

  /// Pinned messages of this chat, newest pin first, with an unpin per row.
  Future<void> _openPinned() async {
    final messages = await CacheUtils.getPrivateMessages(widget.userId);
    final pins = await CacheUtils.getPinnedMessages(widget.userId);
    final pinned = messages
        .where((message) => message.id != null && pins.containsKey(message.id))
        .toList()
      ..sort((a, b) => pins[b.id]!.compareTo(pins[a.id]!));
    if (!mounted) {
      return;
    }
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (pinned.isEmpty) ListTile(title: Text('noPinnedMessages'.tr())),
            for (final message in pinned)
              ListTile(
                leading: const Icon(Icons.push_pin),
                title: Text(
                  message.preview.isEmpty ? 'mediaPhoto'.tr() : message.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(DateFormat.yMMMd()
                    .add_Hm()
                    .format(message.sentAt.toLocal())),
                // Hands the instant back to the chat, which scrolls to it and
                // flashes the bubble.
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, message.sentAt);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'unpinMessage'.tr(),
                  onPressed: () async {
                    await MessageActions.togglePin(message, widget.userId,
                        pinned: true);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    await _loadPins();
                  },
                ),
              ),
          ],
        ),
      ),
    );
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

  /// Pick a day and hand it back to the chat page, which jumps to the first
  /// message of that day (or the first one after it).
  Future<void> _jumpToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked != null && mounted) {
      Navigator.pop(context, picked);
    }
  }

  /// Search this conversation. A picked hit is handed back to the chat page,
  /// which jumps to it.
  Future<void> _openSearch() async {
    final user = await CacheUtils.getUserById(widget.userId);
    if (user == null || !mounted) {
      return;
    }
    final picked = await Navigator.of(context)
        .push<DateTime>(stepRoute(MessageSearchPage(user)));
    if (picked != null && mounted) {
      Navigator.pop(context, picked);
    }
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
                    // Search in this conversation
                    SettingsTile(
                      icon: Icons.search,
                      label: 'searchInChat'.tr(),
                      onPressed: _openSearch,
                    ),
                    // Jump to a day
                    SettingsTile(
                      icon: Icons.event,
                      label: 'jumpToDate'.tr(),
                      onPressed: _jumpToDate,
                    ),
                    // Read receipts: off by default, one switch for both
                    // directions of this chat
                    SettingsTile(
                      icon: Icons.done_all,
                      label: 'readReceipts'.tr(),
                      // Tap on the row toggles too; a non-null handler keeps
                      // the row in the enabled colours (a disabled TextButton
                      // greys out its icon and label).
                      onPressed: () => _toggleReadReceipts(!_readReceipts),
                      trailing: Switch(
                        value: _readReceipts,
                        onChanged:
                            _readReceiptsBusy ? null : _toggleReadReceipts,
                      ),
                    ),
                    // Pinned messages, shared with the other participant
                    SettingsTile(
                      icon: Icons.push_pin,
                      label: 'pinnedMessages'.tr(),
                      onPressed: _openPinned,
                      extra: _pins.isEmpty
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text('${_pins.length}'),
                            ),
                    ),
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
                          final deleted =
                              await MessageNotifier().deleteChat(widget.userId);
                          if (!deleted) {
                            Fluttertoast.showToast(
                                msg: 'deleteChatFailed'.tr(),
                                backgroundColor: Colors.red);
                            return;
                          }
                          if (!context.mounted) {
                            return;
                          }
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
