import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../utils/nav_transitions.dart';
import '../utils/cache_utils.dart';
import '../utils/chat_sender.dart';
import '../utils/disappearing.dart';
import '../utils/message_actions.dart';
import '../utils/message_notifier.dart';
import '../utils/dialog_utils.dart';
import '../utils/utils.dart';
import '../utils/theme_utils.dart';
import '../widgets/settings_tile.dart';
import 'chat_media_page.dart';
import 'home_page.dart';
import 'search_page.dart';

class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage(this.userId, {super.key});
  final String userId;

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  Color? _chatThemeColor;
  Map<String, DateTime> _pins = {};
  bool _readReceipts = false;

  /// Agreed disappearing-message timer of this chat, seconds; 0 when off.
  int _disappearing = 0;

  /// Timer the peer proposed and this device has not answered yet.
  int? _disappearingProposal;

  /// A toggle in flight: the switch stays disabled until the server call and
  /// the cache write are done, so it cannot be flipped back and forth.
  bool _readReceiptsBusy = false;

  @override
  void initState() {
    super.initState();
    _loadChatTheme();
    _loadPins();
    _loadReadReceipts();
    _loadDisappearing();
  }

  Future<void> _loadDisappearing() async {
    final agreed = await CacheUtils.getDisappearingSeconds(widget.userId);
    final proposal = await CacheUtils.getDisappearingProposal(widget.userId);
    if (mounted) {
      setState(() {
        _disappearing = agreed;
        _disappearingProposal = proposal;
      });
    }
  }

  /// A timer is agreed by both sides: this device only ever proposes, and the
  /// peer's proposal is what the accept row answers.
  Future<void> _showDisappearingDialog() async {
    final proposal = _disappearingProposal;
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('disappearingSettings'.tr()),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('disappearingHint'.tr()),
          ),
          if (proposal != null)
            ListTile(
              leading: const Icon(Icons.check),
              title: Text(
                  'disappearingAccept'.tr(args: [disappearingLabel(proposal)])),
              onTap: () => Navigator.pop(ctx, proposal),
            ),
          if (proposal != null)
            ListTile(
              leading: const Icon(Icons.close),
              title: Text('disappearingDecline'.tr()),
              onTap: () => Navigator.pop(ctx, -1),
            ),
          const Divider(),
          for (final option in disappearingOptions)
            ListTile(
              title: Text(disappearingLabel(option)),
              trailing: option == _disappearing
                  ? const Icon(Icons.check)
                  : (option == proposal ? const Icon(Icons.schedule) : null),
              onTap: () => Navigator.pop(ctx, option),
            ),
        ],
      ),
    );
    if (chosen == null) {
      return;
    }
    final user = await CacheUtils.getUserById(widget.userId);
    if (user == null) {
      return;
    }
    if (chosen == -1) {
      await CacheUtils.setDisappearingProposal(widget.userId, null);
      await ChatSender.sendSystem(user, 'decline', 0);
    } else if (proposal != null && chosen == proposal) {
      await CacheUtils.setDisappearingSeconds(widget.userId, chosen);
      await CacheUtils.setDisappearingProposal(widget.userId, null);
      await ChatSender.sendSystem(user, 'accept', chosen);
    } else {
      // Nothing changes until the peer accepts, so a proposal is never a new
      // local timer on its own.
      await ChatSender.sendSystem(user, 'propose', chosen);
    }
    await _loadDisappearing();
    MessageNotifier().notify();
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

  /// Opens the attachments of this chat on a page of their own.
  void _openMedia() {
    Navigator.of(context).push(fadeRoute(
        ChatMediaPage(widget.userId, chatThemeColor: _chatThemeColor)));
  }

  /// Open the chat theme dialog: the same palette as the app theme, applied
  /// live. The dialog is themed with the chat color, so it previews itself.
  Future<void> _pickChatTheme() async {
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => Theme(
              data: ThemeUtils.chatTheme(context, _chatThemeColor),
              child: Builder(
                builder: (themedContext) => DialogUtils.chatThemeDialog(
                  themedContext,
                  current: _chatThemeColor,
                  onChanged: _applyChatTheme,
                ),
              ),
            ));
    await _loadChatTheme();
  }

  /// Stores the picked chat color; null falls back to the global theme.
  Future<void> _applyChatTheme(Color? color) async {
    if (color == null) {
      await CacheUtils.clearChatTheme(widget.userId);
    } else {
      await CacheUtils.setChatTheme(widget.userId, color);
    }
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
                    // Attachments of this chat: a page of their own.
                    SettingsTile(
                      icon: Icons.photo_library_outlined,
                      label: 'mediaTitle'.tr(),
                      onPressed: _openMedia,
                    ),
                    // Disappearing messages: a timer both sides agree on.
                    SettingsTile(
                      icon: Icons.timer_outlined,
                      label: 'disappearingSettings'.tr(),
                      onPressed: _showDisappearingDialog,
                      extra: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(_disappearingProposal != null
                            ? 'disappearingProposalShort'.tr(args: [
                                disappearingLabel(_disappearingProposal!)
                              ])
                            : disappearingLabel(_disappearing)),
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
                    Divider(thickness: 1, indent: 10, endIndent: 10),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
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
