import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart' show CameraPreview;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sprintf/sprintf.dart';
import '../utils/dialog_utils.dart';
import '../utils/nav_transitions.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/cache_utils.dart';
import '../utils/chat_scroll.dart';
import '../utils/chat_sender.dart';
import '../utils/live_location.dart';
import '../utils/media_utils.dart';
import '../utils/message_actions.dart';
import '../utils/message_notifier.dart';
import '../utils/presence.dart';
import '../utils/round_video_recorder.dart';
import '../utils/sticker_store.dart';
import '../utils/singleton.dart';
import '../utils/text_envelope.dart';
import '../utils/utils.dart' as utils;
import '../utils/theme_utils.dart';
import '../widgets/attachment_confirm_sheet.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/live_location_bubble.dart';
import '../widgets/typing_dots.dart';
import 'camera_page.dart';
import 'chat_info_page.dart';
import '../widgets/sticker_sheet.dart';
import 'image_editor_page.dart';
import 'video_trim_page.dart';
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

  /// Sliding up while recording locks it: the finger can be lifted and the
  /// recording keeps going until the bar's stop button is tapped.
  bool _recordingLocked = false;

  /// Round video note started by holding the composer's camera button. It lives
  /// only as long as the finger is down.
  RoundVideoRecorder? _noteRecorder;
  bool _isRecordingNote = false;
  bool _noteStarting = false;
  bool _noteStopRequested = false;
  bool _noteCancel = false;
  Duration _noteElapsed = Duration.zero;
  Timer? _noteTimer;

  /// Press that may turn into a round note. A raw [Listener] is used instead of
  /// a long-press recognizer: inside a TextField the field's own recognizer wins
  /// the gesture arena and the press would never reach us.
  Timer? _noteHoldTimer;
  Offset? _notePressOrigin;

  /// The current press was held long enough to start a note, so releasing it
  /// must not also count as a tap that opens the camera.
  bool _noteHoldFired = false;
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

  /// Which pin the strip shows; the list is newest pin first.
  int _pinIndex = 0;

  /// Message the last jump landed on, flashing so the user sees which one it
  /// was; cleared by [_highlightTimer].
  int? _highlightMicros;
  Timer? _highlightTimer;

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
  // Whether the floating "jump to latest" button is up because the viewport is
  // far from the newest message. Hysteresis keeps it from blinking around the
  // threshold while the finger is still moving.
  bool _farFromBottom = false;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    MessageNotifier().addListener(_onMessagesChanged);
    PresenceNotifier.instance.addListener(_onPresenceChanged);
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
    // A chat created since the last announcement must learn we are here; the
    // call is a no-op when presence is off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      utils.Utils.announcePresence();
    });
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

  /// Typing and presence are ephemeral, so the header redraws on every change.
  void _onPresenceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

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
    if (_unseenCount != 0 || _farFromBottom) {
      setState(() {
        _unseenCount = 0;
        _farFromBottom = false;
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
    // Show after scrolling past a short threshold, hide closer to the bottom:
    // one state with two edges, so the button does not flicker on the edge.
    final far = _farFromBottom ? position.pixels > 60 : position.pixels > 120;
    if (far != _farFromBottom) {
      setState(() {
        _farFromBottom = far;
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

  /// Runs [open] with the composer unfocused and unfocuses again afterwards.
  ///
  /// A sheet or a page pushed over the chat hands the focus (and with it the
  /// keyboard) back to the field when it closes; without this the keyboard pops
  /// up on its own after every attachment sheet or message action.
  Future<void> _withoutComposerFocus(Future<void> Function() open) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await open();
    if (!mounted) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  /// Opens the long-press sheet for one message. The pin state of the sheet is
  /// the one this device knows, so the entry reads "unpin" when it applies.
  Future<void> _openMessageActions(PrivateMessage message) {
    final id = message.id;
    return _withoutComposerFocus(() => MessageActions.showSheet(
          context,
          message,
          widget.user.id,
          pinned: id != null && _pins.containsKey(id),
          onSelect: () => _toggleSelected(message),
        ));
  }

  /// Pinned messages this device holds, newest pin first: the strip walks them.
  List<PrivateMessage> get _pinnedInOrder {
    final pinned = <PrivateMessage>[];
    for (final message in _messages) {
      final id = message.id;
      if (id != null && _pins.containsKey(id)) {
        pinned.add(message);
      }
    }
    pinned.sort((a, b) => _pins[b.id]!.compareTo(_pins[a.id]!));
    return pinned;
  }

  /// Steps the strip to the next pinned message and jumps to it.
  Future<void> _cyclePin(List<PrivateMessage> pins) async {
    final next = (_pinIndex + 1) % pins.length;
    setState(() {
      _pinIndex = next;
    });
    await _jumpToMessage(pins[next].sentAt);
  }

  /// Slim strip under the header: one pin, tap to jump, cross to unpin, the
  /// counter to walk the rest.
  Widget _buildPinBar() {
    final pins = _pinnedInOrder;
    if (pins.isEmpty) {
      return const SizedBox.shrink();
    }
    final pinned = pins[_pinIndex % pins.length];
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
              if (pins.length > 1)
                // Without this the strip only ever showed the newest pin and
                // the others were unreachable.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _cyclePin(pins),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_pinIndex % pins.length + 1}/${pins.length}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        const Icon(Icons.expand_more, size: 14),
                      ],
                    ),
                  ),
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

  /// Flashes the bubble a jump landed on, so the target is obvious even when
  /// the message itself looks like its neighbours.
  void _flashMessage(int micros) {
    _highlightTimer?.cancel();
    setState(() => _highlightMicros = micros);
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _highlightMicros = null);
      }
    });
  }

  /// Scrolls to [sentAt], used by the reply quote, the search hits and the
  /// date jump.
  ///
  /// Widening the rendered window is not enough: a list only builds what is
  /// near the viewport, so growing the tail never builds an old message. The
  /// window is therefore cut down to the target first, then the oldest end is
  /// taken and the viewport walks towards newer messages until the target is
  /// built. Walking back from the oldest end covers both a target above the
  /// viewport and one below it.
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
      }
      final context = _messageKeys[micros]?.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(context,
            alignment: 0.2, duration: const Duration(milliseconds: 250));
        _flashMessage(micros);
        return;
      }
      await _settleAtOldest();
      for (var attempt = 0; attempt < 50; attempt++) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        final reached = _messageKeys[micros]?.currentContext;
        if (reached != null && reached.mounted) {
          await Scrollable.ensureVisible(reached,
              alignment: 0.3, duration: const Duration(milliseconds: 250));
          _flashMessage(micros);
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
      {String caption = '',
      int? durationMs,
      List<int>? waveform,
      bool videoNote = false,
      bool viewOnce = false}) async {
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
          fileName: MediaUtils.baseName(file.path),
          waveform: waveform,
          videoNote: videoNote,
          viewOnce: viewOnce);
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
  Future<void> _sendAlbum(List<File> files,
      {String caption = '', bool viewOnce = false}) async {
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
          caption: caption, viewOnce: viewOnce);
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

      final single = files.length == 1;
      final type =
          single ? forcedType ?? MediaUtils.detectType(files.first.path) : null;
      // Any picked attachment can travel as a single view: one visual file, a
      // gallery album or a plain document all burn the same way. Only a single
      // photo or video can be edited first.
      final editable =
          single && (type == MediaType.image || type == MediaType.video);
      final confirmed = await _confirmAttachment(files.length,
          allowViewOnce: true, allowEdit: editable);
      if (confirmed == null) {
        return;
      }
      if (single && confirmed.edit) {
        final edited = await _editAttachment(type!, files.first);
        if (edited == null) {
          return;
        }
        files = [edited];
      }
      if (single) {
        await _sendMedia(type!, files.first,
            caption: confirmed.caption, viewOnce: confirmed.viewOnce);
      } else {
        await _sendAlbum(files,
            caption: confirmed.caption, viewOnce: confirmed.viewOnce);
      }
    } catch (e) {
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
    }
  }

  /// Opens the sticker collection and sends the picked one as it is: a sticker
  /// travels as its own media type, so the recipient draws it without a bubble.
  Future<void> _pickSticker() async {
    Sticker? sticker;
    await _withoutComposerFocus(() async {
      sticker = await StickerSheet.show(context);
    });
    final picked = sticker;
    if (picked == null) {
      return;
    }
    final bytes = await MediaUtils.decryptAtRest(picked.path);
    final sent = await ChatSender.sendMedia(
        widget.user, MediaType.sticker, bytes,
        fileName: MediaUtils.baseName(picked.path));
    _afterSend(sent, '');
  }

  /// Opens the in-app camera. What comes back is a photo or a video, and it
  /// goes through the same confirm sheet as a gallery pick.
  Future<void> _captureFromCamera() async {
    File? file;
    await _withoutComposerFocus(() async {
      file = await CameraPage.open(context);
    });
    final captured = file;
    if (captured == null) {
      return;
    }
    final type = MediaUtils.detectType(captured.path);
    await _pickAndSend(() async => [captured],
        forcedType:
            type == MediaType.video ? MediaType.video : MediaType.image);
  }

  /// The tap that ends a hold must not open the camera: the button sees the
  /// release as a tap as well.
  void _openCameraUnlessNote() {
    if (_noteHoldFired || _isRecordingNote || _noteStarting) {
      return;
    }
    _captureFromCamera();
  }

  /// A press on the camera button starts the hold timer; a tap still opens the
  /// camera through the button itself.
  void _onCameraPressStart(PointerDownEvent event) {
    // The press is inside the field's tap region, which would focus it and
    // raise the keyboard over the note preview.
    FocusScope.of(context).unfocus();
    _notePressOrigin = event.position;
    _noteHoldFired = false;
    _noteHoldTimer?.cancel();
    _noteHoldTimer = Timer(const Duration(milliseconds: 400), () {
      _noteHoldTimer = null;
      _noteHoldFired = true;
      _startRoundNote();
    });
  }

  void _onCameraPressMove(PointerMoveEvent event) {
    final origin = _notePressOrigin;
    if (origin == null || !_isRecordingNote) {
      return;
    }
    final cancel = event.position.dx - origin.dx < -80;
    if (cancel != _noteCancel) {
      setState(() => _noteCancel = cancel);
    }
  }

  void _onCameraPressEnd(PointerEvent event) {
    _noteHoldTimer?.cancel();
    _noteHoldTimer = null;
    _notePressOrigin = null;
    if (_isRecordingNote) {
      _stopRoundNote();
    } else if (_noteStarting) {
      // Released while the camera was still opening.
      _noteStopRequested = true;
    }
  }

  /// Starts a round video note from the composer. It runs only while the finger
  /// is down; releasing sends it, sliding left throws it away.
  Future<void> _startRoundNote() async {
    if (_isRecordingNote || _noteStarting || _isSending) {
      return;
    }
    _noteStarting = true;
    FocusScope.of(context).unfocus();
    final recorder = RoundVideoRecorder();
    try {
      if (!await recorder.start()) {
        await recorder.dispose();
        await Fluttertoast.showToast(
            msg: 'cameraUnavailable'.tr(), backgroundColor: Colors.red);
        return;
      }
    } finally {
      _noteStarting = false;
    }
    if (!mounted) {
      await recorder.dispose();
      return;
    }
    setState(() {
      _noteRecorder = recorder;
      _isRecordingNote = true;
      _noteCancel = false;
      _noteElapsed = Duration.zero;
    });
    // The press lands inside the field's tap region, which can hand the focus
    // (and the keyboard) back once the preview is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    });
    _noteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _noteElapsed += const Duration(seconds: 1));
      if (_noteElapsed >= RoundVideoRecorder.maxLength) {
        _stopRoundNote();
      }
    });
    // The finger was lifted while the camera was still opening.
    if (_noteStopRequested) {
      _noteStopRequested = false;
      await _stopRoundNote();
    }
  }

  /// Stops the round note and sends it, unless it was dragged away.
  Future<void> _stopRoundNote() async {
    _noteTimer?.cancel();
    _noteTimer = null;
    final recorder = _noteRecorder;
    _noteRecorder = null;
    final cancelled = _noteCancel;
    _noteCancel = false;
    if (mounted) {
      setState(() => _isRecordingNote = false);
    }
    if (recorder == null) {
      return;
    }
    if (cancelled) {
      await recorder.cancel();
      return;
    }
    final file = await recorder.stop();
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
    if (file == null) {
      return;
    }
    await _sendMedia(MediaType.video, file, videoNote: true);
  }

  /// The circle above the composer while a round note is being recorded.
  Widget _buildRoundNotePreview() {
    final controller = _noteRecorder?.controller;
    final color = _noteCancel ? Colors.red : chatTheme.colorScheme.primary;
    final ready = controller != null && controller.value.isInitialized;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: SizedBox(
              width: 150,
              height: 150,
              child: ready
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.previewSize?.height ?? 150,
                        height: controller.value.previewSize?.width ?? 150,
                        child: CameraPreview(controller),
                      ),
                    )
                  : const ColoredBox(
                      color: Colors.black26,
                      child: Center(child: CircularProgressIndicator()),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fiber_manual_record,
                  size: 12, color: Colors.red),
              const SizedBox(width: 4),
              Text(
                '${_formatRecordDuration(_noteElapsed)} · ${'slideToCancel'.tr()}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Runs the editor for one picked attachment. Returns null when the user
  /// backs out, which aborts the send instead of silently sending the original.
  Future<File?> _editAttachment(MediaType type, File file) async {
    if (type == MediaType.image) {
      final bytes = await file.readAsBytes();
      if (!mounted) {
        return null;
      }
      final edited = await ImageEditorPage.open(context, bytes);
      if (edited == null) {
        return null;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/whisper_edited_${DateTime.now().microsecondsSinceEpoch}.png';
      return File(path)..writeAsBytesSync(edited, flush: true);
    }
    if (!mounted) {
      return null;
    }
    return VideoTrimPage.open(context, file);
  }

  /// Sends one fix as a location message. No coordinates are read until the
  /// user picks this action, and they travel only inside the ciphertext.
  Future<void> _sendCurrentLocation() async {
    // A location is a message of its own, so the single view is a choice made
    // here rather than in an attachment sheet.
    final viewOnce = await showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('attachLocation'.tr()),
        children: [
          ListTile(
            leading: const Icon(Icons.place),
            title: Text('attachLocation'.tr()),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off),
            title: Text('attachViewOnce'.tr()),
            subtitle: Text('viewOnceHint'.tr()),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (viewOnce == null || !mounted) {
      return;
    }
    setState(() => _isSending = true);
    try {
      final position = await LiveLocationSharer.currentPosition();
      if (position == null) {
        await Fluttertoast.showToast(
            msg: 'locationUnavailable'.tr(), backgroundColor: Colors.red);
        return;
      }
      final sent = await ChatSender.sendLocation(
          widget.user, position.latitude, position.longitude,
          accuracy: position.accuracy, viewOnce: viewOnce);
      _afterSend(sent, '');
    } catch (e) {
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  /// Live location is opt-in, ends on its own and can be stopped in the banner.
  Future<void> _startLiveLocation() async {
    const options = [15, 60, 480];
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('liveLocationShare'.tr()),
        children: [
          for (final option in options)
            ListTile(
              title: Text('liveLocationFor'.tr(args: ['$option min'])),
              onTap: () => Navigator.pop(ctx, option),
            ),
        ],
      ),
    );
    if (minutes == null) {
      return;
    }
    // The first frame needs a GPS fix and a round trip: without a sending state
    // the sheet closes into a silent screen with nothing to look at.
    setState(() => _isSending = true);
    try {
      final started = await LiveLocationSharer.instance
          .start(widget.user, Duration(minutes: minutes));
      if (started && mounted) {
        setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  /// Bottom sheet with a caption field; returns the caption and the view-once
  /// choice, or null to cancel.
  Future<AttachmentConfirmResult?> _confirmAttachment(int count,
      {bool allowViewOnce = false, bool allowEdit = false}) {
    return AttachmentConfirmSheet.show(
      context,
      count: count,
      allowViewOnce: allowViewOnce,
      allowEdit: allowEdit,
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
    _withoutComposerFocus(() => showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: Text('attachGallery'.tr()),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSend(MediaUtils.pickMultipleMediaFromGallery);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.emoji_emotions_outlined),
                    title: Text('attachStickers'.tr()),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickSticker();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text('attachFile'.tr()),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSend(MediaUtils.pickMultipleFiles,
                          filesOnly: true);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.place),
                    title: Text('attachLocation'.tr()),
                    onTap: () {
                      Navigator.pop(ctx);
                      _sendCurrentLocation();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.my_location),
                    title: Text('attachLiveLocation'.tr()),
                    onTap: () {
                      Navigator.pop(ctx);
                      _startLiveLocation();
                    },
                  ),
                ],
              ),
            );
          },
        ));
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
      _recordingLocked = false;
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
    final waveform = controller.waveform;
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
        durationMs: recorded.durationMs, waveform: waveform);
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

  /// Composer: a paperclip inside the field on the left, one round action
  /// beside the field on the right — mic while it is empty, send once there is
  /// text — painted in the chat's colour.
  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 4, 8, 4),
      // Stretching the row makes the button exactly as tall as the field, so
      // the two are aligned however many lines the field grows to.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  TextField(
                    controller: _controllerMessage,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    onChanged: (value) {
                      // The receiver clears the indicator on its own; this only
                      // throttles the frames and stays silent when the user opted
                      // out.
                      if (value.trim().isNotEmpty) {
                        utils.Utils.sendTypingHint(widget.user.id);
                      }
                    },
                    contentInsertionConfiguration:
                        ContentInsertionConfiguration(
                      allowedMimeTypes: const ['image/gif', 'image/webp'],
                      onContentInserted: _onKeyboardContentInserted,
                    ),
                    decoration: InputDecoration(
                      hintText: 'yourMessage'.tr(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      // Room for the buttons that float above the field.
                      prefixIcon: const SizedBox(width: 40),
                      suffixIcon: const SizedBox(width: 40),
                      filled: true,
                      fillColor: chatTheme.brightness == Brightness.dark
                          ? chatTheme.colorScheme.surfaceBright
                          : chatTheme.colorScheme.surfaceDim,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  // The paperclip and the camera sit above the field, not in
                  // it: a press inside the TextField's tap region focuses it and
                  // flashes the keyboard, which must not happen while a round
                  // note is recording.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _composerIcon(
                        icon: Icons.attach_file,
                        label: 'attachButton'.tr(),
                        tooltip: 'attachButton'.tr(),
                        onPressed: _isSending ? null : _showAttachSheet,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Listener(
                        onPointerDown: _onCameraPressStart,
                        onPointerMove: _onCameraPressMove,
                        onPointerUp: _onCameraPressEnd,
                        onPointerCancel: _onCameraPressEnd,
                        child: _composerIcon(
                          icon: Icons.photo_camera_outlined,
                          label: 'attachCamera'.tr(),
                          onPressed: _isSending ? null : _openCameraUnlessNote,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controllerMessage,
              builder: (context, value, _) {
                // A send in flight shows here whatever the field holds:
                // encrypting and uploading a large attachment, probing a video
                // or waiting for a GPS fix takes a while, and the bubble is not
                // there yet.
                if (_isSending) {
                  return _composerButton(
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  );
                }
                if (value.text.trim().isNotEmpty) {
                  return _composerButton(
                    onPressed: _sendMessage,
                    child: const Icon(Icons.send),
                  );
                }
                // Hold-to-record voice message. The bar is overlaid while
                // recording, so this detector stays mounted and its long-press
                // end still fires.
                return GestureDetector(
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressMoveUpdate: (details) {
                    if (_recordingLocked) {
                      return;
                    }
                    final offset = details.localOffsetFromOrigin;
                    if (offset.dy < -60) {
                      setState(() {
                        _recordingLocked = true;
                        _cancelRecording = false;
                      });
                      return;
                    }
                    final shouldCancel = offset.dx < -80;
                    if (shouldCancel != _cancelRecording) {
                      setState(() {
                        _cancelRecording = shouldCancel;
                      });
                    }
                  },
                  onLongPressEnd: (_) {
                    // A locked recording outlives the gesture: it stops from
                    // the bar, which is all the release used to do.
                    if (_isRecording && !_recordingLocked) {
                      _stopRecording();
                    } else if (!_isRecording) {
                      _stopRequested = true;
                    }
                  },
                  child: _composerButton(
                    onPressed: () async {
                      await Fluttertoast.showToast(msg: 'holdToRecord'.tr());
                    },
                    child: const Icon(Icons.mic),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// A plain icon beside the composer. Compact on purpose: three full-width
  /// buttons would squeeze the field, which is the part that carries the width.
  Widget _composerIcon({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    String? tooltip,
  }) {
    final button = IconButton(
      icon: Icon(icon),
      iconSize: 22,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 44),
      tooltip: tooltip,
      onPressed: onPressed,
    );
    return tooltip == null
        ? Semantics(button: true, label: label, child: button)
        : button;
  }

  /// The round action beside the composer, filled with the chat's colour. It
  /// takes the row's height, so it is a circle while the field has one line.
  Widget _composerButton({Widget? child, VoidCallback? onPressed}) {
    final color = chatTheme.colorScheme.primary;
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black87;
    return SizedBox(
      width: 48,
      child: Material(
        color: color,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: IconTheme(
            data: IconThemeData(color: onColor),
            child: Center(child: child),
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
              _recordingLocked
                  ? 'recordingLocked'.tr()
                  : (_cancelRecording
                      ? 'releaseToCancel'.tr()
                      : 'slideToCancel'.tr()),
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
    // The picked chat color itself: this helper runs above the chat Theme, so
    // Theme.of(context) would be the app theme.
    final color = _chatThemeColor ?? Singleton().appTheme.color;
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
      PrivateMessage message, PrivateMessage? older, PrivateMessage? newer,
      {bool? showAvatar}) {
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
      highlight: _highlightMicros == micros,
      showAvatar: showAvatar,
      readAt: micros == _lastOwnMicros && _readReceipts ? _peerReadAt : null,
      onSelect: () => _toggleSelected(message),
      onActions: () => _openMessageActions(message),
      onReactions: () =>
          MessageActions.showReactions(context, message, widget.user.id),
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

  /// When the live-location session of this chat started, null when there is
  /// none. Ordering the bubble by it keeps the chat chronological.
  DateTime? _liveLocationStart() {
    if (LiveLocationSharer.instance.isSharing(widget.user.id)) {
      return LiveLocationSharer.instance.startedAt;
    }
    // Only while a position is still live: a stopped session leaves no bubble.
    if (PresenceNotifier.instance.liveLocation(widget.user.id) == null) {
      return null;
    }
    return PresenceNotifier.instance.liveStartedAt(widget.user.id);
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
    // The live location takes the place of the message that would carry it:
    // right after everything sent before the session started. -1 marks it in
    // the day bucket.
    final liveStart = _liveLocationStart();
    // Where the marker sits in the timeline: after visible[liveAfter], -1 when
    // it precedes every message. -1 in a day bucket marks the marker itself.
    var liveAfter = -1;
    final liveMine = LiveLocationSharer.instance.isSharing(widget.user.id);
    if (liveStart != null) {
      final firstNewer = visible.indexWhere((m) => m.sentAt.isAfter(liveStart));
      liveAfter = (firstNewer < 0 ? visible.length : firstNewer) - 1;
      final day = DateTime(liveStart.year, liveStart.month, liveStart.day);
      final bucket = days.putIfAbsent(day, () => []);
      var at = bucket.indexWhere((i) => visible[i].sentAt.isAfter(liveStart));
      if (at < 0) {
        at = bucket.length;
      }
      bucket.insert(at, -1);
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
              if (position < 0) {
                // The avatar belongs to whoever ends the run, here the marker
                // itself when nothing follows it.
                return LiveLocationBubble(widget.user,
                    showAvatar: !liveMine && liveAfter == visible.length - 1);
              }
              final message = visible[position];
              return _buildBubble(
                message,
                position > 0 ? visible[position - 1] : null,
                position < visible.length - 1 ? visible[position + 1] : null,
                // The marker continues the peer's run, so a message right
                // before it is not the one that closes it.
                showAvatar: !liveMine && position == liveAfter ? false : null,
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
    _noteHoldTimer?.cancel();
    MessageNotifier().removeListener(_onMessagesChanged);
    PresenceNotifier.instance.removeListener(_onPresenceChanged);
    _scrollController.removeListener(_onScroll);
    WidgetsBinding.instance.removeObserver(_metricsObserver);
    _recordTimer?.cancel();
    _highlightTimer?.cancel();
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
              onPressed: () => _withoutComposerFocus(() =>
                  MessageActions.showSheet(context, single, widget.user.id)),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.user.username),
            // One line of live status; it disappears when nothing is known so
            // the header keeps its plain height.
            if (PresenceNotifier.instance.statusText(widget.user.id)
                case final status?)
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
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
                    if (_isRecordingNote) _buildRoundNotePreview(),
                    if (PresenceNotifier.instance.isTyping(widget.user.id))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // The same avatar the bubbles and the chat list
                              // draw, one size smaller.
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: widget.user.avatarColor,
                                child: Text(
                                  widget.user.username.isNotEmpty
                                      ? widget.user.username[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: widget.user.avatarTextColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              TypingDots(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
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
                          // Floating "down" button: up whenever the viewport is
                          // far from the newest message, and carrying the count
                          // of what arrived while the user was reading above.
                          Positioned(
                            right: 16,
                            bottom: _composerHeight + 16,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.8, end: 1)
                                      .animate(animation),
                                  child: child,
                                ),
                              ),
                              child: !_firstLoad &&
                                      (_farFromBottom || _unseenCount > 0)
                                  ? FloatingActionButton.small(
                                      key: const ValueKey('jumpToLatest'),
                                      heroTag: 'jumpToBottom',
                                      tooltip: 'jumpToLatest'.tr(),
                                      onPressed: () =>
                                          _jumpToBottom(animate: true),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.arrow_downward,
                                              size: 16),
                                          if (_unseenCount > 1)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 2),
                                              child: Text('$_unseenCount',
                                                  style: const TextStyle(
                                                      fontSize: 11)),
                                            ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Right under the header, over the list: the pin is where the
                // eye looks first and the composer stays clean.
                if (_pinnedInOrder.isNotEmpty)
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
