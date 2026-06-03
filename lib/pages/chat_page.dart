import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' show MultipartFile;
import 'package:page_transition/page_transition.dart';
import 'package:provider/provider.dart';
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';
import 'package:whisper_websocket_client_dart/models/new_private_message.dart';
import 'package:whisper_websocket_client_dart/models/ws_message.dart';
import '../models/private_message.dart';
import '../models/user.dart';
import '../utils/cache_utils.dart';
import '../utils/crypto_utils.dart';
import '../utils/media_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import '../widgets/chat_bubble.dart';
import 'package:basic_utils/basic_utils.dart' as bu;
import 'chat_info_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage(this.user, {super.key});
  final User user;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

// Transaprent AppBar: https://ckreymborg.medium.com/how-to-create-a-glassmorphism-frosted-glass-appbar-in-flutter-fb217ce1b4ca

class _ChatPageState extends State<ChatPage> {
  // Add controller for text input
  final TextEditingController _controllerMessage = TextEditingController();
  // Add list for messages
  List<PrivateMessage> _messages = [];
  // Buttons
  bool _isSending = false;
  // ScrollController for content
  final ScrollController _scrollController = ScrollController();
  // Indicates whether messages are being load for the first time
  bool _firstLoad = true;
  // Voice recording state
  bool _isRecording = false;
  bool _cancelRecording = false;
  MediaRecorderController? _recorderController;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    // Load messages from cache
    _loadMessages();
    // Load concept message
    getConceptMessage();
  }

  Future<void> getConceptMessage() async {
    String? conceptMsg = await CacheUtils.getMessageConcept(widget.user.id);
    if (conceptMsg != null) {
      _controllerMessage.text = conceptMsg;
    }
  }

  Future<void> _loadMessages() async {
    _messages = await MessageNotifier().getMessages(widget.user.id);
    MessageNotifier().notify();
    setState(() {});
  }

  /// Send message
  Future<void> _sendMessage() async {
    debugPrint(_controllerMessage.text.length.toString());
    if (_controllerMessage.text.isEmpty) {
      return;
    }
    setState(() {
      _isSending = true;
    });
    await Utils.wsConnect();
    // Send message
    if (Singleton().wsClient.isConnected) {
      // Encrypt message content
      Map<String, Uint8List> data;
      try {
        data = await CryptoUtils.encryptMessageData(
            utf8.encode(_controllerMessage.text),
            bu.CryptoUtils.rsaPublicKeyFromPem(widget.user.publicKey));
      } catch (e) {
        await Fluttertoast.showToast(
            msg: e.toString(), backgroundColor: Colors.red);
        setState(() {
          _isSending = false;
        });
        return;
      }
      DateTime sentAt;
      try {
        sentAt = Singleton().wsClient.sendMessage(WsMessage.privateMessage(
            NewPrivateMessage(widget.user.id, data['encryptedData']!,
                data['encryptedKey']!, data['nonce']!, data['mac']!)));
        // Save user to cache
        if (widget.user.publicKey != '' &&
            widget.user.username != '' &&
            !widget.user.isInBox) {
          CacheUtils.addUser(widget.user);
        }
        // Add message to cache
        await MessageNotifier().addMessages(widget.user.id, [
          PrivateMessage(Singleton().profile.user.id, _controllerMessage.text,
              sentAt, sentAt, true)
        ]);
        // Reset text
        _controllerMessage.text = '';
        // Delete concept
        await CacheUtils.deleteMessageConcept(widget.user.id);
      } catch (e) {
        await Fluttertoast.showToast(
            msg: e.toString(), backgroundColor: Colors.red);
      }
    } else {
      await Fluttertoast.showToast(
          msg: 'wsOffline'.tr(), backgroundColor: Colors.red);
    }
    setState(() {
      _isSending = false;
    });
  }

  /// Send a media attachment: encrypt for transport, upload, embed an encrypted
  /// reference in the message, store the file encrypted-at-rest and add an
  /// optimistic bubble.
  Future<void> _sendMedia(MediaType type, File file,
      {String caption = '', int? durationMs}) async {
    setState(() {
      _isSending = true;
    });
    try {
      final bytes = await file.readAsBytes();

      // Probe metadata depending on the media type.
      int? width;
      int? height;
      int? duration = durationMs;
      if (type == MediaType.image || type == MediaType.gif) {
        final probe = await MediaUtils.imageDimensions(bytes);
        width = probe.width;
        height = probe.height;
      } else if (type == MediaType.video) {
        final probe = await MediaUtils.videoMetadata(file.path);
        width = probe.width;
        height = probe.height;
        duration ??= probe.durationMs;
      }

      await Utils.wsConnect();
      if (!Singleton().wsClient.isConnected) {
        await Fluttertoast.showToast(
            msg: 'wsOffline'.tr(), backgroundColor: Colors.red);
        return;
      }

      // Transport encryption with an ephemeral per-file key.
      final transport = await MediaUtils.encryptForTransport(bytes);

      // Upload the ciphertext over HTTP.
      final uploadResponse = await Utils.callApi(
        () => Singleton().mediaApi.uploadMedia(
              widget.user.id,
              MultipartFile.fromBytes('file', transport.blob,
                  filename: 'media.bin'),
            ),
        rethrowErr: true,
      );
      if (uploadResponse == null || uploadResponse.id == null) {
        await Fluttertoast.showToast(
            msg: 'mediaUploadFailed'.tr(), backgroundColor: Colors.red);
        return;
      }
      final mediaId = uploadResponse.id!;

      // Build the encrypted reference and wrap it in the message envelope.
      final reference = MediaReference(
        mediaId,
        transport.key,
        type,
        transport.blob.length,
        width: width,
        height: height,
        durationMs: duration,
      );
      final envelope = MediaUtils.buildMediaEnvelope(reference, caption);

      // E2E-encrypt the envelope for the recipient.
      final data = await CryptoUtils.encryptMessageData(
          envelope, bu.CryptoUtils.rsaPublicKeyFromPem(widget.user.publicKey));

      // Send over the WebSocket.
      final sentAt = Singleton().wsClient.sendMessage(WsMessage.privateMessage(
          NewPrivateMessage(widget.user.id, data['encryptedData']!,
              data['encryptedKey']!, data['nonce']!, data['mac']!)));

      // Persist the recipient if needed.
      if (widget.user.publicKey != '' &&
          widget.user.username != '' &&
          !widget.user.isInBox) {
        CacheUtils.addUser(widget.user);
      }

      // Store the original media encrypted-at-rest for our own bubble.
      final localPath = await MediaUtils.encryptAtRest(bytes);

      // Optimistic local message.
      await MessageNotifier().addMessages(widget.user.id, [
        PrivateMessage(
          Singleton().profile.user.id,
          caption,
          sentAt,
          sentAt,
          true,
          mediaId: mediaId,
          mediaTypeStr: type.name,
          localPath: localPath,
          mediaSize: bytes.length,
          width: width,
          height: height,
          durationMs: duration,
          downloadStatus: MediaDownloadStatus.ready,
        )
      ]);

      // The caption (taken from the text field) was consumed -> clear it.
      if (caption.isNotEmpty && _controllerMessage.text == caption) {
        _controllerMessage.text = '';
        await CacheUtils.deleteMessageConcept(widget.user.id);
      }
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

  /// Pick media using [picker], detect its type (unless [forcedType] is set)
  /// and send it, using any typed text as the caption.
  Future<void> _pickAndSend(
      Future<File?> Function() picker, MediaType? forcedType) async {
    try {
      final file = await picker();
      if (file == null) {
        return;
      }
      final type = forcedType ?? MediaUtils.detectType(file.path);
      final caption = _controllerMessage.text.trim();
      await _sendMedia(type, file, caption: caption);
    } catch (e) {
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
    }
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
                  _pickAndSend(
                      MediaUtils.pickImageFromCamera, MediaType.image);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: Text('attachVideoCamera'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSend(
                      MediaUtils.pickVideoFromCamera, MediaType.video);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text('attachGallery'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSend(MediaUtils.pickMediaFromGallery, null);
                },
              ),
              ListTile(
                leading: const Icon(Icons.gif_box),
                title: Text('attachGif'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSend(MediaUtils.pickGif, MediaType.gif);
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text('attachFile'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSend(MediaUtils.pickFile, null);
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
    if (_isRecording || _isSending) {
      return;
    }
    final controller = MediaRecorderController();
    if (!await controller.hasPermission()) {
      await controller.dispose();
      await Fluttertoast.showToast(
          msg: 'micPermissionDenied'.tr(), backgroundColor: Colors.red);
      return;
    }
    try {
      await controller.start();
    } catch (e) {
      await controller.dispose();
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
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
  }

  /// Finish recording and send (unless the gesture was cancelled).
  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    final controller = _recorderController;
    _recorderController = null;
    final cancelled = _cancelRecording;
    setState(() {
      _isRecording = false;
    });
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
                        icon: const Icon(Icons.send),
                      );
                    }
                    // Hold-to-record voice message.
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              _cancelRecording
                  ? 'releaseToCancel'.tr()
                  : 'slideToCancel'.tr(),
              style: TextStyle(color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            _cancelRecording ? Icons.delete : Icons.arrow_back,
            color: color,
          ),
        ],
      ),
    );
  }

  /// Get ListView with content
  ListView _getContent(List<PrivateMessage> messages) {
    _firstLoad = false;
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      controller: _scrollController,
      reverse: false,
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Header with avatar (will appear at the top)
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
                      child: Text('legendaryChat'.tr(),
                          textAlign: TextAlign.center)),
                ],
              ),
            ),
          );
        }
        // Return chat bubble
        final previousMessage = index > 1 ? messages[index - 2] : null;
        final message = messages[index - 1];
        final nextMessage = index < messages.length ? messages[index] : null;
        return ChatBubble(previousMessage, message, nextMessage, widget.user);
      },
    );
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorderController?.dispose();
    _controllerMessage.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<MessageNotifier>();

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
                    CircleAvatar(
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
                  ],
                ),
                leadingWidth: 96, // Increase width to accommodate both icons
                // Title
                title: Text(widget.user.username),
                // Action buttons
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info),
                    tooltip: 'infoButton'.tr(),
                    onPressed: () {
                      // Push info page
                      Navigator.of(context).push(PageTransition(
                          duration: const Duration(milliseconds: 300),
                          reverseDuration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          type: PageTransitionType.rightToLeftJoined,
                          child: ChatInfoPage(widget.user.id),
                          childCurrent: widget));
                    },
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
              child: FutureBuilder<List<PrivateMessage>>(
                  future: notifier.getMessages(widget.user.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _firstLoad) {
                      return Center(
                        child: Transform.scale(
                          scale: 1.5,
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    // Set data
                    if (snapshot.hasData) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollController
                            .jumpTo(_scrollController.position.maxScrollExtent);
                      });
                      _messages = snapshot.data!;
                    }
                    // Return messages
                    return _getContent(_messages);
                  }),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _isRecording ? _buildRecordingBar() : _buildInputBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
