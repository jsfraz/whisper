import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:sprintf/sprintf.dart';
import '../utils/dialog_utils.dart';
import '../utils/nav_transitions.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/cache_utils.dart';
import '../utils/chat_scroll.dart';
import '../utils/chat_sender.dart';
import '../utils/media_utils.dart';
import '../utils/message_actions.dart';
import '../utils/message_notifier.dart';
import '../utils/singleton.dart';
import '../utils/text_envelope.dart';
import '../utils/utils.dart' as utils;
import '../utils/theme_utils.dart';
import '../widgets/attachment_confirm_sheet.dart';
import '../widgets/chat_bubble.dart';
import 'chat_info_page.dart';
import 'forward_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage(this.user, {super.key});
  final User user;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

// Transaprent AppBar: https://ckreymborg.medium.com/how-to-create-a-glassmorphism-frosted-glass-appbar-in-flutter-fb217ce1b4ca

class _ChatPageState extends State<ChatPage> {
  /// Messages added per scroll-up step (incremental loading).
  static const int _pageSize = 30;

  // Add controller for text input
  final TextEditingController _controllerMessage = TextEditingController();
  // Add list for messages
  List<PrivateMessage> _messages = [];
  // How many of the newest messages are rendered
  int _visibleCount = _pageSize;
  // Buttons
  bool _isSending = false;
  // ScrollController for content
  final ScrollController _scrollController = ScrollController();
  // Indicates whether messages are being load for the first time
  bool _firstLoad = true;
  // Guards against overlapping cache reads
  bool _loading = false;
  // A change arrived mid-read: run one more pass when it ends
  bool _reloadRequested = false;
  // True only around our own read, which notifies on purpose (home list row)
  bool _selfRead = false;
  // Guards against overlapping history requests
  bool _historyLoading = false;
  // Guards against overlapping "grow the window upwards" passes
  bool _growing = false;
  // A jump walks the list itself; window growth would move the offset under it
  bool _jumping = false;
  // Whether the newest archive page was already asked for
  bool _historyLoaded = false;
  // Cursor for the next (older) archive page, null when the archive ends
  String? _historyCursor;
  // Voice recording state
  bool _isRecording = false;
  bool _recordingStarting = false;
  bool _stopRequested = false;
  bool _cancelRecording = false;
  MediaRecorderController? _recorderController;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  // Per-chat theme override, null means the global theme
  Color? _chatThemeColor;

  /// The message the composer is quoting, null when not replying.
  PrivateMessage? _replyTo;

  /// Oldest message that was unread when the chat opened: the "new messages"
  /// divider. Captured before this page marks everything read.
  DateTime? _unreadAnchor;
  final GlobalKey _unreadDividerKey = GlobalKey();

  /// Client timestamps (microseconds) of the messages picked in multi-select.
  final Set<int> _selected = {};

  /// Bubble keys by client timestamp, for jumping to a quoted message.
  final Map<int, GlobalKey> _messageKeys = {};

  /// Pinned message ids of this chat with the instant of the pin.
  Map<String, DateTime> _pins = {};

  /// Whether this chat publishes and shows read receipts.
  bool _readReceipts = false;

  /// Instant up to which the other participant has read this chat.
  DateTime? _peerReadAt;

  /// Client timestamp of the newest own message: only that one carries the
  /// read tick.
  int? _lastOwnMicros;

  /// Instant this device already told the server about, so an idle re-render
  /// does not send the same cursor again.
  DateTime? _publishedReadAt;
  Timer? _readPublish;

  /// The composer floats over the message list, so the list reserves its
  /// measured height at the bottom and slides behind the bar above it.
  final GlobalKey _composerKey = GlobalKey();
  double _composerHeight = 0;

  /// Newest message the viewport has already shown at the bottom; anything
  /// after it while scrolled up counts as unseen.
  int _newestSeenSentAt = 0;
  int _unseenCount = 0;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    MessageNotifier().addListener(_onMessagesChanged);
    _scrollController.addListener(_onScroll);
    _metricsObserver = _KeyboardObserver(() {
      if (_atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    });
    WidgetsBinding.instance.addObserver(_metricsObserver);
    _start();
    // Load concept message
    getConceptMessage();
    // Load per-chat theme
    _loadChatTheme();
  }

  /// The read state must be captured before the chat marks it read, otherwise
  /// there is no divider left to draw.
  Future<void> _start() async {
    final firstUnread = await CacheUtils.firstUnreadSentAt(widget.user.id);
    if (mounted && firstUnread != null) {
      setState(() {
        _unreadAnchor = firstUnread;
      });
    }
    await _loadMessages();
    // Then top the conversation up from the server archive
    _loadHistory();
  }

  /// Keeps the newest message on screen when the keyboard opens.
  late final _KeyboardObserver _metricsObserver;

  /// Reload the conversation from the cache when messages or media state change.
  void _onMessagesChanged() {
    // Our own read notifies too (it marks messages read); do not re-enter.
    if (_selfRead) {
      return;
    }
    _loadMessages();
  }

  /// Whether the viewport sits at the newest message. The list is reversed, so
  /// the newest message is at offset zero and older ones have larger offsets.
  bool get _atBottom {
    if (!_scrollController.hasClients) {
      return true;
    }
    return _scrollController.position.pixels <= 40;
  }

  /// Load the conversation once per change instead of once per build.
  Future<void> _loadMessages() async {
    if (_loading) {
      // Reading the cache already; the running pass may predate this change.
      _reloadRequested = true;
      return;
    }
    if (!mounted) {
      return;
    }
    _loading = true;
    final first = _firstLoad;
    final wasAtBottom = _atBottom;
    try {
      // The read notifies as a side effect; keep that out of the listener.
      final List<PrivateMessage> messages;
      _selfRead = true;
      try {
        messages = await MessageNotifier().getMessages(widget.user.id);
      } finally {
        _selfRead = false;
      }
      if (!mounted) {
        return;
      }
      // The first content frame decrypts every visible attachment, so keep it
      // out of the push animation and let the spinner ride along instead.
      if (first) {
        await _waitForRouteAnimation();
      }
      if (!mounted) {
        return;
      }
      final newest =
          messages.isEmpty ? 0 : messages.last.sentAt.microsecondsSinceEpoch;
      final pins = await CacheUtils.getPinnedMessages(widget.user.id);
      final peerReadAt = await CacheUtils.getPeerReadAt(widget.user.id);
      final readReceipts =
          await CacheUtils.isReadReceiptsEnabled(widget.user.id);
      if (!mounted) {
        return;
      }
      var lastOwn = 0;
      for (final message in messages.reversed) {
        if (message.isMe) {
          lastOwn = message.sentAt.microsecondsSinceEpoch;
          break;
        }
      }
      setState(() {
        _messages = messages;
        _pins = pins;
        _peerReadAt = peerReadAt;
        _readReceipts = readReceipts;
        _lastOwnMicros = lastOwn == 0 ? null : lastOwn;
        if (!first) {
          if (wasAtBottom) {
            _unseenCount = 0;
          } else if (newest > _newestSeenSentAt) {
            _unseenCount += messages
                .where((message) =>
                    !message.isMe &&
                    message.sentAt.microsecondsSinceEpoch > _newestSeenSentAt)
                .length;
          }
        }
        _newestSeenSentAt = newest;
        _firstLoad = false;
      });
      if (first || wasAtBottom) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) {
          return;
        }
        _jumpToBottom();
        if (first) {
          await _jumpToFirstUnread();
        }
      }
      // Reading the chat is what moves the cursor; the peer's ticks follow.
      _publishReadCursor();
    } finally {
      _loading = false;
      if (_reloadRequested) {
        _reloadRequested = false;
        if (mounted) {
          await _loadMessages();
        }
      }
    }
  }

  /// Completes once the page transition that opened this page has finished.
  Future<void> _waitForRouteAnimation() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      return;
    }
    final done = Completer<void>();
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(onStatus);
        if (!done.isCompleted) {
          done.complete();
        }
      }
    }

    animation.addStatusListener(onStatus);
    await done.future;
  }

  void _jumpToBottom({bool animate = false}) {
    if (!_scrollController.hasClients) {
      return;
    }
    // Reversed list: the newest message is at offset zero.
    if (animate) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(0);
    }
    if (_unseenCount != 0) {
      setState(() {
        _unseenCount = 0;
      });
    }
  }

  /// Takes the oldest end over a few frames: the first jump only reaches the
  /// estimated extent, and the list lays out the real end further on.
  Future<void> _settleAtOldest() async {
    for (var pass = 0; pass < 5; pass++) {
      if (!_scrollController.hasClients) {
        return;
      }
      final before = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(before);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      if ((_scrollController.position.maxScrollExtent - before).abs() < 1) {
        return;
      }
    }
  }

  /// Opens the chat on the first message the user has not read yet.
  Future<void> _jumpToFirstUnread() async {
    if (_unreadAnchor == null) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    final context = _unreadDividerKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    await Scrollable.ensureVisible(context,
        alignment: 0.15, duration: const Duration(milliseconds: 250));
  }

  /// Extend the rendered window when the user scrolls towards older messages.
  void _onScroll() {
    if (_jumping || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (_atBottom && _unseenCount != 0) {
      setState(() {
        _unseenCount = 0;
      });
    }
    // Reversed list: older messages are at the far end of the scroll extent.
    if (position.pixels < position.maxScrollExtent - 200) {
      return;
    }
    if (_visibleCount < _messages.length) {
      _growWindow(_pageSize);
    } else if (_historyCursor != null) {
      // The cache ran out: ask the server for the page above it.
      _loadHistory(older: true);
    }
  }

  /// Renders more messages above the viewport without moving what is on screen.
  ///
  /// The list is reversed, so the extra messages are appended past the current
  /// end of the scroll extent and the viewport does not need any compensation.
  Future<void> _growWindow(int by) async {
    if (_growing || !mounted) {
      return;
    }
    _growing = true;
    setState(() {
      _visibleCount += by;
    });
    await WidgetsBinding.instance.endOfFrame;
    _growing = false;
  }

  /// Fetch one page of the conversation from the server archive.
  ///
  /// The first call fills a chat this device never had (a fresh install, or a
  /// message older than anything local); later calls walk backwards when the
  /// user scrolls past the oldest message.
  Future<void> _loadHistory({bool older = false}) async {
    if (_historyLoading || (older && _historyCursor == null)) {
      return;
    }
    if (!older && _historyLoaded) {
      return;
    }
    if (!utils.Utils.isOnline) {
      return;
    }
    _historyLoading = true;
    try {
      final page = await utils.Utils.callApi(
          () => Singleton().messagesApi.getHistory(widget.user.id,
              before: older ? _historyCursor : null, limit: _pageSize),
          showError: false);
      if (page == null || !mounted) {
        return;
      }
      _historyLoaded = true;
      _historyCursor = page.nextCursor;
      // The account may have cleared this chat on another device: drop what
      // this one still holds before the page is written back.
      if (page.clearedAt != null) {
        await CacheUtils.applyConversationClearedAt(
            widget.user.id, page.clearedAt!.toLocal());
        MessageNotifier().notify();
      }
      // Pins are shared and the page always carries the whole set, so this is
      // also how an unpin that happened on another device lands here.
      final pins = {
        for (final pin in page.pins) pin.messageId: pin.pinnedAt.toLocal(),
      };
      await CacheUtils.replacePinnedMessages(widget.user.id, pins);
      if (mounted) {
        setState(() {
          _pins = pins;
        });
      }
      for (final peer in page.peers) {
        await CacheUtils.addUser(
            User(peer.id, peer.username, peer.publicKey, peer.admin));
      }
      if (page.messages.isEmpty) {
        return;
      }
      await utils.Utils.storeHistoryPage(page.messages);
      if (!mounted) {
        return;
      }
      // Show the page that just arrived without making the user scroll again.
      // Reversed list: the page is appended past the current end, so the
      // viewport stays where the user left it.
      setState(() {
        _visibleCount += page.messages.length;
      });
    } finally {
      _historyLoading = false;
    }
  }

  /// Opens the long-press sheet for one message. The pin state of the sheet is
  /// the one this device knows, so the entry reads "unpin" when it applies.
  void _openMessageActions(PrivateMessage message) {
    final id = message.id;
    MessageActions.showSheet(
      context,
      message,
      widget.user.id,
      pinned: id != null && _pins.containsKey(id),
      onSelect: () => _toggleSelected(message),
    );
  }

  /// The newest pinned message this device still holds, null when none is left.
  PrivateMessage? get _newestPin {
    PrivateMessage? newest;
    DateTime? newestAt;
    for (final message in _messages) {
      final id = message.id;
      if (id == null) {
        continue;
      }
      final at = _pins[id];
      if (at == null) {
        continue;
      }
      if (newestAt == null || at.isAfter(newestAt)) {
        newest = message;
        newestAt = at;
      }
    }
    return newest;
  }

  /// Slim strip under the header: the newest pin, tap to jump, cross to unpin.
  Widget _buildPinBar() {
    final pinned = _newestPin;
    if (pinned == null) {
      return const SizedBox.shrink();
    }
    final preview = pinned.preview;
    return Material(
      // Opaque in the header's tint: the strip sits over the message list, so a
      // translucent fill would let bubbles show through it.
      color: chatBackground(tintAlpha: 0.32),
      child: InkWell(
        onTap: () => _jumpToMessage(pinned.sentAt),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  preview.isEmpty ? 'mediaPhoto'.tr() : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              if (_pins.length > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('+${_pins.length - 1}',
                      style: const TextStyle(fontSize: 10)),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                tooltip: 'unpinMessage'.tr(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                onPressed: () => MessageActions.togglePin(
                    pinned, widget.user.id,
                    pinned: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Publishes how far this chat was read, debounced: scrolling through a burst
  /// of messages should cost one request, not one per message.
  void _publishReadCursor() {
    if (!_readReceipts || _messages.isEmpty) {
      return;
    }
    final newest = _messages.last.sentAt;
    if (_publishedReadAt != null && !newest.isAfter(_publishedReadAt!)) {
      return;
    }
    _readPublish?.cancel();
    _readPublish = Timer(const Duration(seconds: 1), () async {
      final at = _messages.isEmpty ? null : _messages.last.sentAt;
      if (at == null) {
        return;
      }
      if (await utils.Utils.sendReadCursor(widget.user.id, at) && mounted) {
        _publishedReadAt = at;
      }
    });
  }

  /// Load the draft message saved when leaving the chat.
  Future<void> getConceptMessage() async {
    String? conceptMsg = await CacheUtils.getMessageConcept(widget.user.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _controllerMessage.text = conceptMsg ?? '';
    });
  }

  /// Load the per-chat theme override.
  Future<void> _loadChatTheme() async {
    Color? color = await CacheUtils.getChatTheme(widget.user.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _chatThemeColor = color;
    });
  }

  Future<void> _openChatInfo() async {
    // The info page hands back a timestamp when a search hit or a date was
    // picked there.
    final target = await Navigator.of(context)
        .push<DateTime>(stepRoute(ChatInfoPage(widget.user.id)));
    // The theme (and possibly the user) may have changed while it was open.
    await _loadChatTheme();
    await _loadMessages();
    if (target != null && mounted) {
      await _jumpTo(target);
    }
  }

  /// Jumps to [target], or to the first message after it: a search hit is an
  /// exact instant, a picked day is midnight.
  Future<void> _jumpTo(DateTime target) async {
    if (_messages.isEmpty) {
      return;
    }
    var index = _messages.indexWhere((message) => message.sentAt == target);
    if (index < 0) {
      index = _messages.indexWhere((message) => message.sentAt.isAfter(target));
    }
    if (index < 0) {
      await Fluttertoast.showToast(
          msg: 'noMessagesOnDate'.tr(), backgroundColor: Colors.orange);
      return;
    }
    await _jumpToMessage(_messages[index].sentAt);
  }

  // ---------------------------------------------------------------------------
  // Reply and multi-select
  // ---------------------------------------------------------------------------

  /// Quote [message] in the composer.
  void _startReply(PrivateMessage message) {
    if (_selectionMode) {
      return;
    }
    setState(() {
      _replyTo = message;
    });
  }

  /// Adds or removes [message] from the selection; leaving it empty closes the
  /// selection mode.
  void _toggleSelected(PrivateMessage message) {
    final micros = message.sentAt.microsecondsSinceEpoch;
    setState(() {
      if (!_selected.remove(micros)) {
        _selected.add(micros);
      }
    });
  }

  void _clearSelection() {
    setState(_selected.clear);
  }

  /// Messages currently picked, oldest first.
  List<PrivateMessage> get _selectedMessages => _messages
      .where((message) =>
          _selected.contains(message.sentAt.microsecondsSinceEpoch))
      .toList();

  Future<void> _copySelected() async {
    final text = _selectedMessages
        .map((message) => message.message)
        .where((text) => text.isNotEmpty)
        .join('\n');
    _clearSelection();
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    Fluttertoast.showToast(msg: 'copiedText'.tr());
  }

  Future<void> _forwardSelected() async {
    final messages = _selectedMessages;
    if (messages.isEmpty) {
      return;
    }
    _clearSelection();
    await Navigator.of(context).push(stepRoute(ForwardPage(messages)));
  }

  void _deleteSelected() {
    final messages = _selectedMessages;
    if (messages.isEmpty) {
      return;
    }
    DialogUtils.yesNoDialog(
        context, 'deleteMessageConfirm'.tr(), 'deleteMessageConfirmText'.tr(),
        () async {
      for (final message in messages) {
        await CacheUtils.deletePrivateMessage(widget.user.id, message);
      }
      _clearSelection();
      MessageNotifier().notify();
    });
  }

  /// Scrolls to [sentAt], used by the reply quote, the search hits and the
  /// date jump.
  ///
  /// Widening the rendered window is not enough: a list only builds what is
  /// near the viewport, so growing the tail never builds an old message. The
  /// fast path therefore cuts the window down to the target, which puts it one
  /// screen from the oldest end, and jumping to that end lands on it. The slow
  /// path walks a viewport at a time towards older messages for a target
  /// already inside a large window but far from the screen.
  Future<void> _jumpToMessage(DateTime sentAt) async {
    final micros = sentAt.microsecondsSinceEpoch;
    _jumping = true;
    try {
      final index = _messages.indexWhere((message) => message.sentAt == sentAt);
      if (index < 0) {
        return;
      }
      final needed = windowForAddition(_messages.length, index);
      if (needed > _visibleCount) {
        setState(() {
          _visibleCount = needed;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        // Reversed list: the target sits at the far end of the window.
        await _settleAtOldest();
        if (!mounted) {
          return;
        }
      }
      final context = _messageKeys[micros]?.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(context,
            alignment: 0.2, duration: const Duration(milliseconds: 250));
        return;
      }
      for (var attempt = 0; attempt < 50; attempt++) {
        if (!_scrollController.hasClients) {
          return;
        }
        final position = _scrollController.position;
        final next =
            nextJumpOffset(position.pixels, position.viewportDimension);
        if (next == position.pixels) {
          return;
        }
        _scrollController.jumpTo(next);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) {
          return;
        }
        final reached = _messageKeys[micros]?.currentContext;
        if (reached != null && reached.mounted) {
          await Scrollable.ensureVisible(reached,
              alignment: 0.3, duration: const Duration(milliseconds: 250));
          return;
        }
      }
    } finally {
      _jumping = false;
    }
  }

  /// Send the typed text.
  Future<void> _sendMessage() async {
    final text = _controllerMessage.text;
    if (text.isEmpty) {
      return;
    }
    final quoted = _replyTo;
    final reply = quoted == null
        ? null
        : ReplyRef(
            senderId: quoted.senderId,
            sentAt: quoted.sentAt,
            preview: ReplyRef.previewOf(quoted.preview),
          );
    setState(() {
      _isSending = true;
    });
    if (await ChatSender.sendText(widget.user, text, reply: reply)) {
      _controllerMessage.text = '';
      setState(() {
        _replyTo = null;
      });
      await CacheUtils.deleteMessageConcept(widget.user.id);
    }
    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }

  /// Send a media attachment: probe what the type needs, then the shared send
  /// path (encrypt, upload, persist a bubble, send).
  Future<void> _sendMedia(MediaType type, File file,
      {String caption = '', int? durationMs}) async {
    setState(() {
      _isSending = true;
    });
    try {
      final bytes = await file.readAsBytes();
      final probe = await _probe(type, bytes, file.path, durationMs);
      final sent = await ChatSender.sendMedia(widget.user, type, bytes,
          caption: caption,
          width: probe.width,
          height: probe.height,
          durationMs: probe.durationMs,
          fileName: MediaUtils.baseName(file.path));
      _afterSend(sent, caption);
    } catch (e) {
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  /// Send several attachments as one album message.
  Future<void> _sendAlbum(List<File> files, {String caption = ''}) async {
    setState(() {
      _isSending = true;
    });
    try {
      final attachments = <OutgoingAttachment>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final type = MediaUtils.detectType(file.path);
        final probe = await _probe(type, bytes, file.path, null);
        attachments.add(OutgoingAttachment(
          type: type,
          bytes: bytes,
          width: probe.width,
          height: probe.height,
          durationMs: probe.durationMs,
          fileName: MediaUtils.baseName(file.path),
        ));
      }
      final sent = await ChatSender.sendAlbum(widget.user, attachments,
          caption: caption);
      _afterSend(sent, caption);
    } catch (e) {
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  /// Clear the composer when the caption was consumed by a successful send.
  void _afterSend(bool sent, String caption) {
    if (sent && caption.isNotEmpty && _controllerMessage.text == caption) {
      _controllerMessage.text = '';
      CacheUtils.deleteMessageConcept(widget.user.id);
    }
  }

  /// Width/height/duration for the types that need them.
  Future<MediaProbe> _probe(
      MediaType type, Uint8List bytes, String path, int? durationMs) async {
    if (type == MediaType.image || type == MediaType.gif) {
      return MediaUtils.imageDimensions(bytes);
    }
    if (type == MediaType.video) {
      final probe = await MediaUtils.videoMetadata(path);
      return MediaProbe(
        width: probe.width,
        height: probe.height,
        durationMs: probe.durationMs ?? durationMs,
      );
    }
    return MediaProbe(durationMs: durationMs);
  }

  /// Pick one or more files, then confirm with an optional caption.
  ///
  /// [forcedType] fixes the type for camera picks; [filesOnly] rejects photos
  /// and videos (the "File" entry must stay a document picker).
  Future<void> _pickAndSend(Future<List<File>> Function() picker,
      {MediaType? forcedType, bool filesOnly = false}) async {
    try {
      final picked = await picker();
      if (picked.isEmpty) {
        return;
      }
      var files = picked;
      if (filesOnly) {
        files =
            picked.where((file) => !MediaUtils.isVisualMedia(file)).toList();
        if (files.length != picked.length) {
          await Fluttertoast.showToast(
              msg: 'fileTypeNotAllowed'.tr(), backgroundColor: Colors.orange);
        }
        if (files.isEmpty) {
          return;
        }
      }

      // Cheap size check before reading anything into memory.
      for (final file in files) {
        if (!MediaUtils.uploadFits(await file.length())) {
          await Fluttertoast.showToast(
              msg:
                  '${'fileTooLarge'.tr()} ${MediaUtils.formatBytes(MediaUtils.maxUploadBytes)}',
              backgroundColor: Colors.red);
          return;
        }
      }

      final caption = await _confirmAttachment(files.length);
      if (caption == null) {
        return;
      }
      if (files.length == 1) {
        final type = forcedType ?? MediaUtils.detectType(files.first.path);
        await _sendMedia(type, files.first, caption: caption);
      } else {
        await _sendAlbum(files, caption: caption);
      }
    } catch (e) {
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
    }
  }

  /// Bottom sheet with a caption field; returns the caption, or null to cancel.
  Future<String?> _confirmAttachment(int count) {
    return AttachmentConfirmSheet.show(
      context,
      count: count,
      initialCaption: _controllerMessage.text.trim(),
      theme: ThemeUtils.chatTheme(context, _chatThemeColor),
      backgroundColor: chatBackground(tintAlpha: 0.18),
    );
  }

  /// GIF/WebP inserted straight from the keyboard (Gboard image keyboard).
  Future<void> _onKeyboardContentInserted(
      KeyboardInsertedContent content) async {
    final bytes = content.data;
    if (bytes == null || bytes.isEmpty) {
      await Fluttertoast.showToast(
          msg: 'gifFromKeyboardFailed'.tr(), backgroundColor: Colors.red);
      return;
    }
    final extension = content.mimeType == 'image/webp' ? 'webp' : 'gif';
    final file = await MediaUtils.writeTempBytes(bytes, extension);
    await _sendMedia(MediaType.gif, file);
  }

  /// Show the attachment options bottom sheet.
  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: Text('attachCamera'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSend(() async {
                    final file = await MediaUtils.pickImageFromCamera();
                    return file == null ? <File>[] : [file];
                  }, forcedType: MediaType.image);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: Text('attachVideoCamera'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSend(() async {
                    final file = await MediaUtils.pickVideoFromCamera();
                    return file == null ? <File>[] : [file];
                  }, forcedType: MediaType.video);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text('attachGallery'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSend(MediaUtils.pickMultipleMediaFromGallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text('attachFile'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSend(MediaUtils.pickMultipleFiles, filesOnly: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Start recording a voice message (hold-to-record).
  Future<void> _startRecording() async {
    if (_isRecording || _recordingStarting || _isSending) {
      return;
    }
    _recordingStarting = true;
    final controller = MediaRecorderController();
    try {
      if (!await controller.hasPermission()) {
        await Fluttertoast.showToast(
            msg: 'micPermissionDenied'.tr(), backgroundColor: Colors.red);
        await controller.dispose();
        return;
      }
      await controller.start();
    } catch (e) {
      await controller.dispose();
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
      return;
    } finally {
      _recordingStarting = false;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _recorderController = controller;
      _isRecording = true;
      _cancelRecording = false;
      _recordDuration = Duration.zero;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _recordDuration += const Duration(seconds: 1);
        });
      }
    });
    // The finger was lifted while the recorder was still starting.
    if (_stopRequested) {
      _stopRequested = false;
      await _stopRecording();
    }
  }

  /// Finish recording and send (unless the gesture was cancelled).
  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    final controller = _recorderController;
    _recorderController = null;
    final cancelled = _cancelRecording;
    _cancelRecording = false;
    if (mounted) {
      setState(() {
        _isRecording = false;
      });
    }
    if (controller == null) {
      return;
    }
    if (cancelled) {
      await controller.cancel();
      await controller.dispose();
      return;
    }
    final recorded = await controller.stop();
    await controller.dispose();
    if (recorded == null) {
      return;
    }
    // Ignore accidental taps that produce a near-empty recording.
    if (recorded.durationMs < 800) {
      await MediaUtils.deleteLocalFile(recorded.file.path);
      await Fluttertoast.showToast(
          msg: 'voiceTooShort'.tr(), backgroundColor: Colors.orange);
      return;
    }
    await _sendMedia(MediaType.voice, recorded.file,
        durationMs: recorded.durationMs);
  }

  /// Stop and drop the recording (bar button).
  Future<void> _cancelRecordingGesture() async {
    if (!_isRecording) {
      return;
    }
    setState(() {
      _cancelRecording = true;
    });
    await _stopRecording();
  }

  String _formatRecordDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Default message input bar: attach inside the field on the left, mic or
  /// send on the right.
  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.only(right: 5, left: 5),
      child: TextField(
        controller: _controllerMessage,
        minLines: 1,
        maxLines: 5,
        textInputAction: TextInputAction.newline,
        contentInsertionConfiguration: ContentInsertionConfiguration(
          allowedMimeTypes: const ['image/gif', 'image/webp'],
          onContentInserted: _onKeyboardContentInserted,
        ),
        decoration: InputDecoration(
          hintText: 'yourMessage'.tr(),
          // The attach button lives inside the field, mirroring the mic.
          prefixIcon: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'attachButton'.tr(),
            onPressed: _isSending ? null : _showAttachSheet,
          ),
          filled: true,
          fillColor: chatTheme.brightness == Brightness.dark
              ? chatTheme.colorScheme.surfaceBright
              : chatTheme.colorScheme.surfaceDim,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controllerMessage,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              if (hasText) {
                return IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                );
              }
              // Hold-to-record voice message. The bar is overlaid while
              // recording, so this detector stays mounted and its
              // long-press end still fires.
              return GestureDetector(
                onLongPressStart: (_) {
                  if (!_isSending) {
                    _startRecording();
                  }
                },
                onLongPressMoveUpdate: (details) {
                  final shouldCancel = details.localOffsetFromOrigin.dx < -80;
                  if (shouldCancel != _cancelRecording) {
                    setState(() {
                      _cancelRecording = shouldCancel;
                    });
                  }
                },
                onLongPressEnd: (_) {
                  if (_isRecording) {
                    _stopRecording();
                  } else {
                    _stopRequested = true;
                  }
                },
                child: IconButton(
                  onPressed: _isSending
                      ? null
                      : () async {
                          await Fluttertoast.showToast(
                              msg: 'holdToRecord'.tr());
                        },
                  icon: const Icon(Icons.mic),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Quoted message above the composer, dismissable.
  Widget _buildReplyBar() {
    final reply = _replyTo!;
    final author = reply.isMe
        ? 'meText'.tr()
        : (widget.user.username.isNotEmpty ? widget.user.username : '?');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: chatTheme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: chatTheme.colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  author,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: chatTheme.colorScheme.primary,
                  ),
                ),
                Text(
                  reply.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: chatTheme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'cancel'.tr(),
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              setState(() {
                _replyTo = null;
              });
            },
          ),
        ],
      ),
    );
  }

  /// Bar shown while recording a voice message.
  Widget _buildRecordingBar() {
    final color = _cancelRecording ? Colors.red : chatTheme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chatTheme.brightness == Brightness.dark
            ? chatTheme.colorScheme.surfaceBright
            : chatTheme.colorScheme.surfaceDim,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, color: color),
          const SizedBox(width: 8),
          Text(_formatRecordDuration(_recordDuration)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _cancelRecording ? 'releaseToCancel'.tr() : 'slideToCancel'.tr(),
              style: TextStyle(color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'cancel'.tr(),
            onPressed: _cancelRecordingGesture,
            icon: const Icon(Icons.delete),
            color: Colors.red,
          ),
          IconButton(
            tooltip: 'send'.tr(),
            onPressed: _stopRecording,
            icon: const Icon(Icons.send),
            color: color,
          ),
        ],
      ),
    );
  }

  /// Avatar + name header shown above the oldest message.
  Widget _buildHeader() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: widget.user.avatarColor,
              child: Text(
                widget.user.username.isNotEmpty
                    ? widget.user.username[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 40,
                  color: widget.user.avatarTextColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.user.username,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 50),
                child: Text('legendaryChat'.tr(), textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  /// The "new messages" divider, drawn above the first unread message.
  Widget _buildUnreadDivider() {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      key: _unreadDividerKey,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'newMessages'.tr(),
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Divider(color: color)),
        ],
      ),
    );
  }

  /// Calendar day a message belongs to, in the timezone the bubble shows.
  DateTime _dayOf(PrivateMessage message) {
    final time = (message.isMe ? message.sentAt : message.receivedAt).toLocal();
    return DateTime(time.year, time.month, time.day);
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    if (days <= 0) {
      return 'todayText'.tr();
    }
    if (days == 1) {
      return 'yesterdayText'.tr();
    }
    if (days < 7) {
      return DateFormat.EEEE().format(day);
    }
    if (day.year == now.year) {
      return DateFormat.MMMMd().format(day);
    }
    return DateFormat.yMMMMd().format(day);
  }

  Widget _buildBubble(
      PrivateMessage message, PrivateMessage? older, PrivateMessage? newer) {
    final micros = message.sentAt.microsecondsSinceEpoch;
    final key = _messageKeys.putIfAbsent(micros, () => GlobalKey());
    final showsDivider = _unreadAnchor?.microsecondsSinceEpoch == micros;
    final bubble = ChatBubble(
      older,
      message,
      newer,
      widget.user,
      key: key,
      // The picked chat color itself, not a tonal derivative of it.
      accentColor: _chatThemeColor ?? Singleton().appTheme.color,
      selectionMode: _selectionMode,
      selected: _selected.contains(micros),
      readAt: micros == _lastOwnMicros && _readReceipts ? _peerReadAt : null,
      onSelect: () => _toggleSelected(message),
      onActions: () => _openMessageActions(message),
      onQuickReact: () => MessageActions.react(
          message, widget.user.id, MessageActions.quickReaction),
      onReply: () => _startReply(message),
      onTapQuote: message.isReply
          ? () => _jumpToMessage(message.replyTo!.sentAt)
          : null,
    );
    if (!showsDivider) {
      return bubble;
    }
    // The divider sits above its message and goes away once the day header
    // does not repeat it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_buildUnreadDivider(), bubble],
    );
  }

  /// Messages, grouped by day: each day gets a sticky header.
  Widget _getContent(List<PrivateMessage> messages) {
    final start =
        messages.length > _visibleCount ? messages.length - _visibleCount : 0;
    final visible = messages.sublist(start);
    final hasOlder = start > 0;

    final days = <DateTime, List<int>>{};
    for (var i = 0; i < visible.length; i++) {
      days.putIfAbsent(_dayOf(visible[i]), () => []).add(i);
    }
    final orderedDays = days.keys.toList()..sort();

    // The scroll view is reversed: the first sliver is painted at the bottom
    // of the screen, so the days and their messages go newest first. Offset
    // zero is the newest message, which is why opening the chat needs no jump
    // and older pages cannot move what the user is reading.
    return CustomScrollView(
      controller: _scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // Reversed list: the first sliver sits at the visual bottom, so this
        // spacer keeps the newest message above the composer bar.
        SliverToBoxAdapter(child: SizedBox(height: _composerHeight)),
        for (final day in orderedDays.reversed) ...[
          SliverList.builder(
            itemCount: days[day]!.length,
            itemBuilder: (context, index) {
              final position = days[day]![days[day]!.length - 1 - index];
              final message = visible[position];
              return _buildBubble(
                message,
                position > 0 ? visible[position - 1] : null,
                position < visible.length - 1 ? visible[position + 1] : null,
              );
            },
          ),
          SliverPersistentHeader(
            // A pinned header would stick to the bottom edge in a reversed
            // view, so day separators scroll with their messages instead.
            pinned: false,
            delegate: _DayHeader(
              label: _dayLabel(day),
              textColor: Theme.of(context).colorScheme.onSurfaceVariant,
              background: chatBackground(tintAlpha: 0.35),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: hasOlder
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : _buildHeader(),
        ),
        // The body sits behind the translucent app bar, so the conversation
        // has to start below it: without this the avatar header and the first
        // day separator are painted under the bar.
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.viewPaddingOf(context).top + kToolbarHeight,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    MessageNotifier().removeListener(_onMessagesChanged);
    _scrollController.removeListener(_onScroll);
    WidgetsBinding.instance.removeObserver(_metricsObserver);
    _recordTimer?.cancel();
    if (_readPublish?.isActive ?? false) {
      // Leaving within the debounce window used to drop the cursor; send it
      // now, fire and forget (dispose cannot await).
      _readPublish!.cancel();
      if (_readReceipts && _messages.isNotEmpty) {
        unawaited(
            utils.Utils.sendReadCursor(widget.user.id, _messages.last.sentAt));
      }
    }
    _readPublish?.cancel();
    _recorderController?.dispose();
    _controllerMessage.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Background tinted by the chat color: the M3 surface alone is almost
  /// neutral, so a chat with its own color was indistinguishable from any other.
  ///
  /// [tintAlpha] overrides how much of the color goes in (the AppBar uses more
  /// so the header reads as part of the conversation).
  Color chatBackground({double? tintAlpha}) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _chatThemeColor ?? Singleton().appTheme.color;
    final double alpha = tintAlpha ??
        (Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.12);
    return Color.alphaBlend(accent.withValues(alpha: alpha), scheme.surface);
  }

  /// The chat's own theme. [build] and its helpers run above the chat `Theme`,
  /// so `Theme.of(context)` there is the app theme, not this conversation's.
  ThemeData get chatTheme => ThemeUtils.chatTheme(context, _chatThemeColor);

  /// Repeating doodle pattern behind the messages, recolored by the theme so it
  /// reads on a light and on a dark background.
  DecorationImage chatPattern() {
    return DecorationImage(
      image: const AssetImage('assets/images/chat_bg.png'),
      repeat: ImageRepeat.repeat,
      scale: 3,
      colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
          BlendMode.srcIn),
    );
  }

  /// AppBar color: a stronger tint, kept translucent so the blur still shows.
  Color appBarBackground() {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return chatBackground(tintAlpha: dark ? 0.30 : 0.22)
        .withValues(alpha: 0.85);
  }

  /// Chat AppBar, or the selection AppBar while messages are picked.
  Widget _buildAppBarContent() {
    if (_selectionMode) {
      final single =
          _selectedMessages.length == 1 ? _selectedMessages.first : null;
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: appBarBackground(),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'cancel'.tr(),
          onPressed: _clearSelection,
        ),
        title: Text(sprintf('selectedCount'.tr(), [_selected.length])),
        actions: [
          IconButton(
            icon: Icon(MessageActions.copyIcon),
            tooltip: 'copyMessage'.tr(),
            onPressed: _copySelected,
          ),
          IconButton(
            icon: Icon(MessageActions.forwardIcon),
            tooltip: 'forwardMessage'.tr(),
            onPressed: _forwardSelected,
          ),
          IconButton(
            icon: Icon(MessageActions.deleteIcon),
            tooltip: 'deleteMessageForMe'.tr(),
            onPressed: _deleteSelected,
          ),
          // Save, resend and the rest still live in the single-message sheet.
          if (single != null)
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'moreActions'.tr(),
              onPressed: () =>
                  MessageActions.showSheet(context, single, widget.user.id),
            ),
        ],
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: appBarBackground(),
      leading: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          GestureDetector(
            onTap: _openChatInfo,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: widget.user.avatarColor,
              child: Text(
                widget.user.username.isNotEmpty
                    ? widget.user.username[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 16,
                  color: widget.user.avatarTextColor,
                ),
              ),
            ),
          ),
        ],
      ),
      leadingWidth: 96, // Increase width to accommodate both icons
      // Title
      title: GestureDetector(
        onTap: _openChatInfo,
        behavior: HitTestBehavior.opaque,
        child: Text(widget.user.username),
      ),
      // Action buttons
      actions: [
        IconButton(
          icon: const Icon(Icons.info),
          tooltip: 'infoButton'.tr(),
          onPressed: _openChatInfo,
        ),
      ],
    );
  }

  /// Measures the composer so the list can reserve exactly its height.
  void _measureComposer() {
    final render = _composerKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) {
      return;
    }
    final height = render.size.height;
    if ((height - _composerHeight).abs() > 0.5) {
      setState(() => _composerHeight = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _measureComposer();
      }
    });
    // A bottomNavigationBar is anchored to the screen bottom, not to the
    // keyboard: with edge-to-edge the window is no longer resized for the IME,
    // so the bar has to carry the inset itself or the field hides behind the
    // keyboard. It stays inside the measured composer, so the list reserves
    // the room.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && _messages.isNotEmpty) {
          if (_controllerMessage.text.isNotEmpty) {
            await CacheUtils.setMessageConcept(
                widget.user.id, _controllerMessage.text);
          } else {
            await CacheUtils.deleteMessageConcept(widget.user.id);
          }
        }
      },
      child: Theme(
        data: ThemeUtils.chatTheme(context, _chatThemeColor),
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: chatBackground(),
          appBar: PreferredSize(
            preferredSize: Size(
              double.infinity,
              56.0,
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: _buildAppBarContent(),
              ),
            ),
          ),
          // The message list runs behind the composer bar, so a tall bubble is
          // never cut off at the input's edge.
          extendBody: true,
          // Transparent on purpose: the chat background and the messages
          // slide under the composer instead of a filled band behind it.
          bottomNavigationBar: Container(
            key: _composerKey,
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyTo != null) _buildReplyBar(),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildInputBar(),
                        if (_isRecording)
                          Positioned.fill(child: _buildRecordingBar()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(image: chatPattern()),
            child: Stack(
              children: [
                Column(
                  children: [
                    // Messages and avatar list
                    Expanded(
                      child: Stack(
                        children: [
                          _firstLoad
                              ? Center(
                                  child: Transform.scale(
                                    scale: 1.5,
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : _getContent(_messages),
                          // Floating "down" button with the count of messages that
                          // arrived while the user was reading further up.
                          if (!_firstLoad && _unseenCount > 0)
                            Positioned(
                              right: 16,
                              bottom: _composerHeight + 16,
                              child: FloatingActionButton.small(
                                heroTag: 'jumpToBottom',
                                tooltip: 'jumpToLatest'.tr(),
                                onPressed: () => _jumpToBottom(animate: true),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.arrow_downward, size: 16),
                                    if (_unseenCount > 1)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 2),
                                        child: Text('$_unseenCount',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Right under the header, over the list: the pin is where the
                // eye looks first and the composer stays clean.
                if (_newestPin != null)
                  Positioned(
                    top: kToolbarHeight + MediaQuery.of(context).padding.top,
                    left: 0,
                    right: 0,
                    child: _buildPinBar(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sticky day label above the messages of one calendar day.
class _DayHeader extends SliverPersistentHeaderDelegate {
  _DayHeader({
    required this.label,
    required this.textColor,
    required this.background,
  });

  final String label;
  final Color textColor;
  final Color background;

  @override
  double get minExtent => 34;

  @override
  double get maxExtent => 34;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DayHeader oldDelegate) =>
      oldDelegate.label != label ||
      oldDelegate.textColor != textColor ||
      oldDelegate.background != background;
}

/// Fires [onMetricsChanged] when the keyboard opens or closes.
class _KeyboardObserver extends WidgetsBindingObserver {
  _KeyboardObserver(this.onMetricsChanged);

  final VoidCallback onMetricsChanged;

  @override
  void didChangeMetrics() {
    onMetricsChanged();
  }
}
