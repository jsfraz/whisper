import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../utils/cache_utils.dart';
import '../utils/message_search.dart';

/// Searches one conversation's local history. Messages are stored decrypted,
/// so this is a local scan: nothing is sent anywhere.
///
/// The page returns the timestamp of the picked message; the chat it belongs to
/// jumps there.
class MessageSearchPage extends StatefulWidget {
  const MessageSearchPage(this.peer, {super.key});

  final User peer;

  @override
  State<MessageSearchPage> createState() => _MessageSearchPageState();
}

class _MessageSearchPageState extends State<MessageSearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<MessageHit> _hits = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final query = MessageSearchQuery(
      text: _controller.text,
      conversationId: widget.peer.id,
    );
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
    setState(() {
      _hits = hits;
      _loading = false;
      _searched = true;
    });
  }

  /// A result line with the found text highlighted.
  Widget _snippetText(String text) {
    final scheme = Theme.of(context).colorScheme;
    final needle = _controller.text;
    return Text.rich(
      TextSpan(
        children: [
          for (final part in highlightParts(snippet(text, needle), needle))
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
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _resultTile(MessageHit hit) {
    final message = hit.message;
    final time = DateFormat.MMMd().add_Hm().format(message.sentAt.toLocal());
    return ListTile(
      title: _snippetText(message.preview),
      trailing: Text(
        time,
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      onTap: () => Navigator.pop(context, message.sentAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('searchInChat'.tr())),
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
