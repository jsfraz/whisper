import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/private_message.dart';
import '../utils/disappearing.dart';
import '../utils/message_format.dart';
import '../utils/message_notifier.dart';
import '../utils/singleton.dart';
import 'formatted_text.dart';
import 'media_bubble.dart';

/// One message bubble.
///
/// Long-press enters selection mode; double-tap (or a horizontal swipe) replies.
/// Everything the single-message sheet used to offer lives in the selection
/// app bar, which keeps one gesture per intent.
class ChatBubble extends StatefulWidget {
  final PrivateMessage? previousMessage;
  final PrivateMessage message;
  final PrivateMessage? nextMessage;
  final User user;
  // Fixed for both light and dark mode (see ThemeUtils.bubbleAccent).
  final Color accentColor;

  /// Whether the chat is in multi-select mode.
  final bool selectionMode;

  /// Whether this bubble is part of the current selection.
  final bool selected;

  /// Flashes the bubble after a jump, so the user can see which message the
  /// jump landed on.
  final bool highlight;

  /// Instant up to which the peer read the chat; null when they never
  /// published one (receipts off or nothing read yet).
  final DateTime? readAt;

  /// Toggles this bubble in the selection (tap and long-press).
  final VoidCallback? onSelect;

  /// Opens the action sheet (long-press). Falls back to [onSelect] when unset.
  final VoidCallback? onActions;

  /// Opens the "who reacted" list when the reaction badge is tapped.
  final VoidCallback? onReactions;

  /// Quotes this message in the composer (swipe, and double-tap when no quick
  /// reaction is wired).
  final VoidCallback? onReply;

  /// Double-tap: adds the quick reaction to this message.
  final VoidCallback? onQuickReact;

  /// Jumps to the quoted message.
  final VoidCallback? onTapQuote;

  const ChatBubble(
      this.previousMessage, this.message, this.nextMessage, this.user,
      {required this.accentColor,
      this.selectionMode = false,
      this.selected = false,
      this.highlight = false,
      this.readAt,
      this.onSelect,
      this.onActions,
      this.onReactions,
      this.onReply,
      this.onQuickReact,
      this.onTapQuote,
      super.key});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _showTooltip = false;

  /// Long messages start folded; this is set once the user unfolds one.
  bool _expanded = false;

  /// Text longer than this is folded (about eight lines on a phone).
  static const int _foldLength = 600;

  bool get _foldable =>
      !widget.message.isMedia &&
      !widget.message.isUndecryptable &&
      widget.message.message.length > _foldLength;

  bool get _isLargeEmoji =>
      !widget.message.isMedia &&
      !widget.message.isUndecryptable &&
      isEmojiOnly(widget.message.message) &&
      emojiCount(widget.message.message) <= 3;

  /// Tapping the badge shows who reacted; a bubble without that callback keeps
  /// offering its actions, which is what the badge used to do.
  VoidCallback? get _onBadgeTap =>
      widget.onReactions ?? widget.onActions ?? widget.onSelect;

  /// One badge for all reactions of the bubble: the emoji sit in a single pill
  /// with no gap between them, and a count only when the same emoji came from
  /// more than one participant.
  Widget _reactionBadge() {
    final emojis = widget.message.reactionEmojis;
    final counts = <String, int>{};
    for (final emoji in widget.message.reactions?.values ?? const <String>[]) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < emojis.length; i++) ...[
            if (i > 0) const SizedBox(width: 1),
            Text(
              (counts[emojis[i]] ?? 1) > 1
                  ? '${emojis[i]}${counts[emojis[i]]}'
                  : emojis[i],
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// A control message rendered as one centred line: the disappearing-message
  /// agreement, which belongs to the chat state rather than to a speaker.
  Widget _systemPill(BuildContext context) {
    final message = widget.message;
    final label = disappearingLabel(message.systemSeconds);
    final text = switch (message.systemState) {
      'propose' => 'disappearingProposalPill'.tr(args: [label]),
      'accept' => 'disappearingEnabledPill'.tr(args: [label]),
      'decline' => 'disappearingDeclinedPill'.tr(),
      _ => 'disappearingChanged'.tr(),
    };
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A control message has no bubble of its own: it is one centred line.
    if (widget.message.isSystem) {
      return _systemPill(context);
    }

    bool showAvatar() {
      if (widget.message.isMe) return false;
      // Show avatar if next message is null (last message)
      if (widget.nextMessage == null) return true;
      // Show avatar if next message is from different user
      return widget.nextMessage!.senderId != widget.message.senderId;
    }

    bool isFromSameUser() {
      if (widget.previousMessage == null) return false;
      return widget.previousMessage!.senderId == widget.message.senderId;
    }

    bool shouldShowTime() {
      if (widget.previousMessage == null) return true;

      final previousTime = widget.previousMessage!.isMe
          ? widget.previousMessage!.sentAt
          : widget.previousMessage!.receivedAt;

      final currentTime = widget.message.isMe
          ? widget.message.sentAt
          : widget.message.receivedAt;

      final difference = currentTime.difference(previousTime).inMinutes;
      return difference >= 10;
    }

    String formatDate(DateTime date) {
      final DateTime now = DateTime.now().toLocal();
      final DateTime messageDate = date.toLocal();
      final int daysDifference = messageDate.difference(now).inDays;

      // Today
      if (messageDate.day == now.day &&
          messageDate.month == now.month &&
          messageDate.year == now.year) {
        return DateFormat.Hm().format(messageDate);
      }
      // Yesterday
      else if (daysDifference == -1) {
        return '${'yesterdayText'.tr()} ${DateFormat.Hm().format(messageDate)}';
      }
      // Last week
      else if (daysDifference >= -7) {
        return '${DateFormat.EEEE().format(messageDate)} ${DateFormat.Hm().format(messageDate)}';
      }
      // This year
      else if (messageDate.year == now.year) {
        return '${DateFormat.MMMMd().format(messageDate)} ${DateFormat.Hm().format(messageDate)}';
      }
      // Different year
      else {
        return '${DateFormat.yMMMMd().format(messageDate)} ${DateFormat.Hm().format(messageDate)}';
      }
    }

    Color bubbleBackground() {
      if (widget.message.isMe) {
        return widget.accentColor;
      }
      // The other side stays neutral, only the tone follows the brightness.
      if (Theme.of(context).brightness == Brightness.dark) {
        return Theme.of(context).colorScheme.surfaceContainerHigh;
      }
      return Theme.of(context).colorScheme.surfaceDim;
    }

    Color bubbleTextColor() {
      final backgroundColor = bubbleBackground();
      double luminance = backgroundColor.computeLuminance();
      return luminance > 0.5 ? Colors.black : Colors.white;
    }

    /// Gesture handling: select in selection mode, otherwise tooltip + reply.
    void onTap() {
      if (widget.selectionMode) {
        widget.onSelect?.call();
        return;
      }
      setState(() {
        _showTooltip = !_showTooltip;
      });
    }

    void onLongPress() {
      // A long press in selection mode does nothing: tapping already toggles.
      if (widget.selectionMode) {
        return;
      }
      (widget.onActions ?? widget.onSelect)?.call();
    }

    Widget content() {
      if (widget.message.isMedia) {
        return MediaBubble(
          message: widget.message,
          badge: widget.message.reactionEmojis.isEmpty
              ? null
              : GestureDetector(
                  onTap: _onBadgeTap,
                  child: _reactionBadge(),
                ),
          conversationUserId: widget.user.id,
          bubbleColor: bubbleBackground(),
          textColor: bubbleTextColor(),
          canRetry: widget.message.mediaId != null &&
              MessageNotifier().canRetryMedia(widget.message.mediaId!),
          onRetry: () {
            if (widget.message.mediaId != null) {
              MessageNotifier()
                  .retryMediaDownload(widget.user.id, widget.message.mediaId!);
            }
          },
        );
      }

      final color = bubbleTextColor();
      if (widget.message.isUndecryptable) {
        return Text(
          'messageUndecryptable'.tr(),
          style: TextStyle(color: color, fontStyle: FontStyle.italic),
        );
      }

      final text = FormattedText(
        widget.message.message,
        style: TextStyle(
          color: color,
          fontSize: _isLargeEmoji ? 40 : null,
        ),
        maxLines: _foldable && !_expanded ? 8 : null,
      );
      if (!_foldable) {
        return text;
      }
      return Column(
        crossAxisAlignment: widget.message.isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          text,
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _expanded ? 'showLess'.tr() : 'showFull'.tr(),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    /// The quoted message above the body, tappable to jump to the original.
    Widget quoteBlock() {
      final reply = widget.message.replyTo;
      if (reply == null) {
        return const SizedBox.shrink();
      }
      final color = bubbleTextColor();
      final fromMe = reply.senderId == Singleton().profile.user.id;
      final author = fromMe
          ? 'meText'.tr()
          : (widget.user.username.isNotEmpty ? widget.user.username : '?');
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: widget.onTapQuote,
          child: Container(
            constraints: const BoxConstraints(minWidth: 120),
            padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: color.withValues(alpha: 0.8), width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  author,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  reply.preview.isEmpty ? 'mediaPhoto'.tr() : reply.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bubble = Column(
      crossAxisAlignment: widget.message.isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.message.forwarded)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'forwardedMessage'.tr(),
              style: TextStyle(
                color: bubbleTextColor().withValues(alpha: 0.8),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (widget.message.isReply) quoteBlock(),
        content(),
        if (widget.message.isEdited)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'messageEdited'.tr(),
              style: TextStyle(
                color: bubbleTextColor().withValues(alpha: 0.7),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );

    // Emoji-only messages drop the bubble chrome and read large; an attachment
    // is the bubble, so it is clipped to the corners instead of sitting inside
    // a coloured frame.
    final isMedia = widget.message.isMedia;
    // Animated so a jump flashes in and fades out instead of popping.
    final bubbleBox = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        // A reply needs a surface for its quote; the attachment below fills the
        // rest of the bubble.
        color: isMedia
            ? (widget.message.isReply ? bubbleBackground() : null)
            : (_isLargeEmoji ? null : bubbleBackground()),
        borderRadius: BorderRadius.circular(20),
      ),
      // Above the child: a border in the decoration would sit under an
      // attachment that fills the bubble.
      foregroundDecoration: (widget.selected || widget.highlight)
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      padding: isMedia
          ? (widget.message.isReply
              ? const EdgeInsets.fromLTRB(8, 8, 8, 0)
              : EdgeInsets.zero)
          : (_isLargeEmoji
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
      child: bubble,
    );

    // An attachment clips its own media; the bubble must stay unclipped when a
    // reaction badge hangs over its bottom edge. The wrapper is always there and
    // only stops clipping: toggling Container.clipBehavior adds or drops its
    // clip widget, which re-mounts the attachment and throws the decoded image
    // away - the white flash when a reaction was added.
    final clippedBox = isMedia
        ? ClipRRect(
            borderRadius: BorderRadius.circular(20),
            clipBehavior: widget.message.reactionEmojis.isEmpty
                ? Clip.antiAlias
                : Clip.none,
            child: bubbleBox,
          )
        : bubbleBox;

    // The reactions hang on the bubble's bottom edge as one badge, on the side
    // opposite the bubble's own side, the way a messenger pins them there.
    final bubbleWithBadge =
        widget.message.reactionEmojis.isEmpty || widget.message.isMedia
            ? clippedBox
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  // The room for the badge is part of the stack: a child that
                  // hangs past its parent's edge still paints, but it never
                  // receives the tap that opens the reaction list.
                  Padding(
                    // Same 12 px the badge used to hang by, now reserved
                    // inside the stack so the badge stays tappable.
                    padding: const EdgeInsets.only(bottom: 12),
                    child: clippedBox,
                  ),
                  Positioned(
                    bottom: 0,
                    left: widget.message.isMe ? 8 : null,
                    right: widget.message.isMe ? null : 8,
                    child: GestureDetector(
                      onTap: _onBadgeTap,
                      child: _reactionBadge(),
                    ),
                  ),
                ],
              );

    return Padding(
      padding: EdgeInsets.only(
        left: widget.message.isMe ? 96 : 16,
        right: widget.message.isMe ? 16 : 96,
        top: isFromSameUser() ? 4 : 16,
      ),
      child: Row(
        mainAxisAlignment: widget.message.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.selectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                widget.selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: widget.message.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (_showTooltip && !shouldShowTime()) _tooltip(formatDate),
                if (shouldShowTime()) _tooltip(formatDate),
                GestureDetector(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  onDoubleTap: widget.selectionMode
                      ? null
                      : (widget.onQuickReact ?? widget.onReply),
                  child: Align(
                    alignment: widget.message.isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Row(
                      mainAxisAlignment: widget.message.isMe
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!widget.message.isMe)
                          SizedBox(
                            width: 40, // 32 (avatar) + 8 (padding)
                            child: showAvatar()
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: widget.user.avatarColor,
                                      child: Text(
                                        widget.user.username.isNotEmpty
                                            ? widget.user.username[0]
                                                .toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: widget.user.avatarTextColor,
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: widget.message.isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Padding(
                                // The badge's room is inside the bubble's own
                                // stack, so this one only carries the swipe.
                                padding: EdgeInsets.zero,
                                child: widget.onReply != null &&
                                        !widget.selectionMode
                                    ? Dismissible(
                                        key: ValueKey(
                                            'reply|${widget.message.senderId}'
                                            '|${widget.message.sentAt.microsecondsSinceEpoch}'),
                                        direction: DismissDirection.horizontal,
                                        // The swipe is an action, not a
                                        // delete: the bubble springs back.
                                        confirmDismiss: (_) async {
                                          widget.onReply?.call();
                                          return false;
                                        },
                                        background: _swipeBackground(
                                            Alignment.centerLeft,
                                            bubbleTextColor()),
                                        secondaryBackground: _swipeBackground(
                                            Alignment.centerRight,
                                            bubbleTextColor()),
                                        child: bubbleWithBadge,
                                      )
                                    : bubbleWithBadge,
                              ),
                              // Outgoing messages show a clock while they are
                              // being sent and an error when the send failed.
                              if (widget.message.isMe &&
                                  widget.message.sendStatus != SendStatus.sent)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Tooltip(
                                    message: widget.message.sendStatus ==
                                            SendStatus.failed
                                        ? 'messageSendFailed'.tr()
                                        : 'messageSending'.tr(),
                                    child: Icon(
                                      widget.message.sendStatus ==
                                              SendStatus.failed
                                          ? Icons.error_outline
                                          : Icons.schedule,
                                      size: 13,
                                      color: widget.message.sendStatus ==
                                              SendStatus.failed
                                          ? Colors.red
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              // Only the newest own message carries a tick, and
                              // only when the peer's cursor covers it: a single
                              // "delivered" tick would be a claim this build
                              // cannot back, because the peer's receipt switch
                              // is their business.
                              if (widget.message.isMe && _readByPeer)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Tooltip(
                                    message: 'messageRead'.tr(),
                                    child: Icon(
                                      Icons.done_all,
                                      size: 13,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
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
    );
  }

  /// Whether the peer's read cursor already covers this message.
  bool get _readByPeer {
    final readAt = widget.readAt;
    return readAt != null && !widget.message.sentAt.isAfter(readAt);
  }

  Widget _swipeBackground(Alignment alignment, Color color) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Icon(Icons.reply, color: color.withValues(alpha: 0.7)),
    );
  }

  Widget _tooltip(String Function(DateTime) formatDate) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: Text(
          formatDate(widget.message.isMe
              ? widget.message.sentAt
              : widget.message.receivedAt),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ),
    );
  }
}
