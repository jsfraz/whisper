import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

import '../models/user.dart';
import '../utils/cache_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/message_search.dart';
import '../utils/nav_transitions.dart';
import 'chat_page.dart';

/// Searches the local message store. Messages are stored decrypted, so this is
/// a local scan: nothing is sent anywhere.
///
/// With [peer] the search is scoped to that conversation and the picked
/// message is returned as a timestamp (the caller jumps to it). Without [peer]
/// the results span every conversation and open the chat at the hit.
class MessageSearchPage extends StatefulWidget {
  const MessageSearchPage({this.peer, super.key});

  final User? peer;

  @override
  State<MessageSearchPage> createState() => _MessageSearchPageState();
}

class _MessageSearchPageState extends State<MessageSearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<MessageHit> _hits = [];
  bool _loading = false;
  bool _searched = false;

  /// Media type name, or [MessageSearchQuery.textType]; null matches any.
  String? _type;
  DateTimeRange? _range;

  /// Sender (conversation) filter, only offered in the global search.
  String? _conversationId;
  List<User> _conversations = [];
  final Map<String, User?> _users = {};

  bool get _global => widget.peer == null;

  @override
  void initState() {
    super.initState();
    if (_global) {
      _loadConversations();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final chats = await MessageNotifier().getLatestPrivateMessages();
    if (!mounted) {
      return;
    }
    setState(() {
      _conversations = chats.keys.toList();
    });
  }

  MessageSearchQuery get _query => MessageSearchQuery(
        text: _controller.text,
        conversationId: widget.peer?.id ?? _conversationId,
        from: _range?.start,
        to: _range?.end,
        type: _type,
      );

  void _onTextChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final query = _query;
    if (query.isEmpty) {
      setState(() {
        _hits = [];
        _searched = false;
      });
      return;
    }
    setState(() {
      _loading = true;
    });
    final hits = await CacheUtils.searchMessages(query);
    if (!mounted) {
      return;
    }
    for (final hit in hits) {
      if (_users.containsKey(hit.conversationId)) {
        continue;
      }
      _users[hit.conversationId] =
          await CacheUtils.getUserById(hit.conversationId);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _hits = hits;
      _loading = false;
      _searched = true;
    });
  }

  Future<void> _pickRange() async {
    // Tapping the active chip clears it, which is the only way back to "any
    // date" without reopening the picker.
    if (_range != null) {
      setState(() {
        _range = null;
      });
      await _run();
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _range = picked;
    });
    await _run();
  }

  Future<void> _open(MessageHit hit) async {
    final peer = widget.peer;
    if (peer != null) {
      // The chat page jumps to the picked message.
      Navigator.pop(context, hit.message.sentAt);
      return;
    }
    final user = _users[hit.conversationId];
    if (user == null) {
      return;
    }
    await Navigator.of(context)
        .push(stepRoute(ChatPage(user, jumpTo: hit.message.sentAt)));
  }

  String _displayName(String conversationId) {
    final user = _users[conversationId];
    if (user == null || user.username.isEmpty) {
      return '?';
    }
    return user.username;
  }

  Widget _typeSelector() {
    return DropdownButton<String?>(
      value: _type,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(12),
      hint: Text('anyType'.tr()),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text('anyType'.tr())),
        DropdownMenuItem<String?>(
            value: MessageSearchQuery.textType, child: Text('textOnly'.tr())),
        for (final type in [
          MediaType.image,
          MediaType.video,
          MediaType.voice,
          MediaType.file,
          MediaType.gif,
        ])
          DropdownMenuItem<String?>(
              value: type.name, child: Text('media${_typeLabel(type)}'.tr())),
      ],
      onChanged: (value) async {
        setState(() {
          _type = value;
        });
        await _run();
      },
    );
  }

  /// Suffix of the existing media label keys (mediaPhoto, mediaVideo, ...).
  String _typeLabel(MediaType type) {
    switch (type) {
      case MediaType.image:
        return 'Photo';
      case MediaType.video:
        return 'Video';
      case MediaType.voice:
        return 'Voice';
      case MediaType.file:
        return 'File';
      case MediaType.gif:
        return 'Gif';
    }
  }

  Widget _senderSelector() {
    return DropdownButton<String?>(
      value: _conversationId,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(12),
      hint: Text('anySender'.tr()),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text('anySender'.tr())),
        for (final user in _conversations)
          DropdownMenuItem<String?>(
            value: user.id,
            child: SizedBox(
              width: 140,
              child: Text(
                user.username.isEmpty ? '?' : user.username,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      onChanged: (value) async {
        setState(() {
          _conversationId = value;
        });
        await _run();
      },
    );
  }

  Widget _filters() {
    final label = _range == null
        ? 'anyDate'.tr()
        : '${DateFormat.MMMd().format(_range!.start)}'
            ' – ${DateFormat.MMMd().format(_range!.end)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _typeSelector(),
          FilterChip(
            label: Text(label),
            selected: _range != null,
            avatar: const Icon(Icons.date_range, size: 18),
            onSelected: (_) => _pickRange(),
          ),
          if (_global && _conversations.isNotEmpty) _senderSelector(),
        ],
      ),
    );
  }

  /// A result line with the found text highlighted.
  Widget _snippetText(String text, {int? maxLines}) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          for (final part in highlightParts(
              snippet(text, _controller.text), _controller.text))
            TextSpan(
              text: part.text,
              style: part.match
                  ? TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                      backgroundColor:
                          scheme.primaryContainer.withValues(alpha: 0.8),
                    )
                  : null,
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }

  Widget _resultTile(MessageHit hit) {
    final message = hit.message;
    final user = _users[hit.conversationId];
    final time = DateFormat.MMMd().add_Hm().format(message.sentAt.toLocal());
    final text = message.preview;
    return ListTile(
      leading: _global
          ? CircleAvatar(
              radius: 20,
              backgroundColor:
                  user?.avatarColor ?? Theme.of(context).colorScheme.primary,
              child: Text(
                _displayName(hit.conversationId)[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  color: user?.avatarTextColor ?? Colors.white,
                ),
              ),
            )
          : null,
      title: _global
          ? Text(_displayName(hit.conversationId))
          : _snippetText(text, maxLines: 2),
      subtitle: _global ? _snippetText(text, maxLines: 2) : null,
      trailing: Text(
        time,
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      onTap: () => _open(hit),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_global ? 'searchMessages'.tr() : widget.peer!.username),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _run(),
                decoration: InputDecoration(
                  hintText: 'searchHint'.tr(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'cancel'.tr(),
                          onPressed: () {
                            _controller.clear();
                            _run();
                          },
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            _filters(),
            if (_loading) const LinearProgressIndicator(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (!_searched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'searchEmptyHint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(child: Text('noSearchResults'.tr()));
    }
    return ListView.builder(
      itemCount: _hits.length,
      itemBuilder: (context, index) => _resultTile(_hits[index]),
    );
  }
}
