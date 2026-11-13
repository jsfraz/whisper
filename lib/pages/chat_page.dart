import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:page_transition/page_transition.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/cache_utils.dart';
import '../utils/chat_sender.dart';
import '../utils/media_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/theme_utils.dart';
import '../widgets/chat_bubble.dart';
import 'chat_info_page.dart';

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
  // ScrollController for content (list is reversed: offset 0 is the newest)
  final ScrollController _scrollController = ScrollController();
  // Indicates whether messages are being load for the first time
  bool _firstLoad = true;
  // Guards against overlapping cache reads
  bool _loading = false;
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

  @override
  void initState() {
    super.initState();
    MessageNotifier().addListener(_onMessagesChanged);
    _scrollController.addListener(_onScroll);
    // Load messages from cache
    _loadMessages();
    // Load concept message
    getConceptMessage();
    // Load per-chat theme
    _loadChatTheme();
  }

  /// Reload the conversation from the cache when messages or media state change.
  void _onMessagesChanged() {
    _loadMessages();
  }

  /// Load the conversation once per change instead of once per build.
  Future<void> _loadMessages() async {
    if (_loading || !mounted) {
      return;
    }
    _loading = true;
    try {
      final messages = await MessageNotifier().getMessages(widget.user.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = messages;
        _firstLoad = false;
      });
    } finally {
      _loading = false;
    }
  }

  /// Extend the rendered window when the user scrolls towards older messages.
  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 200 &&
        _visibleCount < _messages.length) {
      setState(() {
        _visibleCount += _pageSize;
      });
    }
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
    await Navigator.of(context).push(PageTransition(
      type: PageTransitionType.rightToLeft,
      child: ChatInfoPage(widget.user.id),
    ));
    // The theme (and possibly the user) may have changed while it was open.
    await _loadChatTheme();
    await _loadMessages();
  }

  /// Send the typed text.
  Future<void> _sendMessage() async {
    final text = _controllerMessage.text;
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _isSending = true;
    });
    if (await ChatSender.sendText(widget.user, text)) {
      _controllerMessage.text = '';
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
  Future<void> _pickAndSend(
      Future<List<File>> Function() picker,
      {MediaType? forcedType,
      bool filesOnly = false}) async {
    try {
      final picked = await picker();
      if (picked.isEmpty) {
        return;
      }
      var files = picked;
      if (filesOnly) {
        files = picked.where((file) => !MediaUtils.isVisualMedia(file)).toList();
        if (files.length != picked.length) {
          await Fluttertoast.showToast(
              msg: 'fileTypeNotAllowed'.tr(),
              backgroundColor: Colors.orange);
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
  Future<String?> _confirmAttachment(int count) async {
    final controller = TextEditingController(text: _controllerMessage.text.trim());
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                count > 1
                    ? '${'sendAlbum'.tr()} ($count)'
                    : 'sendAttachment'.tr(),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                autofocus: true,
                decoration: InputDecoration(hintText: 'addCaption'.tr()),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('cancel'.tr()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: Text('send'.tr()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    return result;
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

  /// Default message input bar (attach + text field + mic/send).
  Widget _buildInputBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'attachButton'.tr(),
          onPressed: _isSending ? null : _showAttachSheet,
        ),
        Expanded(
          child: Padding(
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
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.surfaceBright
                    : Theme.of(context).colorScheme.surfaceDim,
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
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
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
                        final shouldCancel =
                            details.localOffsetFromOrigin.dx < -80;
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
          ),
        ),
      ],
    );
  }

  /// Bar shown while recording a voice message.
  Widget _buildRecordingBar() {
    final color =
        _cancelRecording ? Colors.red : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceBright
            : Theme.of(context).colorScheme.surfaceDim,
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

  /// Reversed list: offset 0 is the newest message, so the chat opens at the
  /// bottom and growing bubbles or the keyboard never strand it mid-list.
  Widget _getContent(List<PrivateMessage> messages) {
    final start = messages.length > _visibleCount
        ? messages.length - _visibleCount
        : 0;
    final visible = messages.sublist(start);
    final hasOlder = start > 0;
    final itemCount = visible.length + 1;

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      controller: _scrollController,
      reverse: true,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Last item is the conversation header (top of the screen).
        if (index == visible.length) {
          if (hasOlder) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _buildHeader();
        }
        // index 0 is the newest message; older messages have higher indices.
        final message = visible[visible.length - 1 - index];
        final position = visible.length - 1 - index;
        final older = position > 0 ? visible[position - 1] : null;
        final newer = position < visible.length - 1
            ? visible[position + 1]
            : null;
        return ChatBubble(older, message, newer, widget.user);
      },
    );
  }

  @override
  void dispose() {
    MessageNotifier().removeListener(_onMessagesChanged);
    _scrollController.removeListener(_onScroll);
    _recordTimer?.cancel();
    _recorderController?.dispose();
    _controllerMessage.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          appBar: PreferredSize(
            preferredSize: Size(
              double.infinity,
              56.0,
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: AppBar(
                  automaticallyImplyLeading: false,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.2),
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
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              // Messages and avatar list
              Expanded(
                child: _firstLoad
                    ? Center(
                        child: Transform.scale(
                          scale: 1.5,
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _getContent(_messages),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildInputBar(),
                      if (_isRecording)
                        Positioned.fill(child: _buildRecordingBar()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
