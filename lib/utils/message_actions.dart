import 'dart:convert';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:whisper_openapi_client_dart/api.dart';

import '../models/private_message.dart';
import '../pages/forward_page.dart';
import 'cache_utils.dart';
import 'chat_sender.dart';
import 'crypto_utils.dart';
import 'dialog_utils.dart';
import 'media_utils.dart';
import 'message_notifier.dart';
import 'singleton.dart';
import 'text_envelope.dart';
import 'utils.dart';
import '../utils/nav_transitions.dart';

/// Actions for a single message, offered by the bubble long-press sheet and by
/// the attachment viewer's overflow menu.
class MessageActions {
  /// Icons shared by the bubble sheet and the viewer's overflow menu, so both
  /// offer the same actions with the same icons.
  static const IconData copyIcon = Icons.copy;
  static const IconData forwardIcon = Icons.forward;
  static const IconData saveIcon = Icons.download;
  static const IconData deleteIcon = Icons.delete;
  static const IconData resendIcon = Icons.refresh;
  static const IconData editIcon = Icons.edit;
  static const IconData pinIcon = Icons.push_pin_outlined;
  static const IconData unpinIcon = Icons.push_pin;
  static const IconData selectIcon = Icons.checklist;

  /// Reaction a double-tap adds, toggled off by a second double-tap.
  static const String quickReaction = '❤️';

  /// Emoji offered by the reaction row. A short fixed set keeps reacting one
  /// tap instead of opening a picker.
  static const List<String> reactionEmojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏'
  ];

  /// Whether [message] can be saved or forwarded (the file must be on disk).
  static bool canSave(PrivateMessage message) =>
      message.isMedia && message.localPath != null;

  /// A view-once attachment may not be passed on: it is one open, for one
  /// conversation.
  static bool canForward(PrivateMessage message) => !message.viewOnce;

  /// Opens a static location in the platform map app. The coordinates leave the
  /// app only through this explicit tap.
  static Future<void> openLocation(LocationRef location,
      {void Function()? onError}) async {
    final uri = Uri.parse(
        'geo:${location.lat},${location.lng}?q=${location.lat},${location.lng}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      onError?.call();
    }
  }

  /// Spends the one view of a view-once attachment: the local copy goes, the
  /// archive row stays as a tombstone and the server records the instant, so
  /// the sender learns it too. The server call is best effort — a torn network
  /// only costs the sender the signal, never the one-view rule.
  static Future<void> consumeViewOnce(
      String conversationUserId, PrivateMessage message) async {
    final id = message.id;
    if (id != null && id.isNotEmpty) {
      try {
        await Utils.callApi(() => Singleton().messagesApi.openMessage(id));
      } catch (_) {
        // The tombstone is local either way.
      }
    }
    await CacheUtils.markMessageOpened(
        conversationUserId, message.sentAt, DateTime.now());
    MessageNotifier().notify();
  }

  /// The emoji row of a reaction sheet: one tap sets the caller's reaction, or
  /// takes it back when it is the one already picked.
  static Widget reactionRow(
      BuildContext context, PrivateMessage message, String conversationUserId) {
    final mine = message.reactions?[Singleton().profile.user.id];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final emoji in reactionEmojis)
            IconButton(
              style: emoji == mine
                  ? IconButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.primary),
                    )
                  : null,
              onPressed: () {
                Navigator.pop(context);
                react(message, conversationUserId, emoji);
              },
              icon: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
        ],
      ),
    );
  }

  /// Reactions grouped by emoji, most used first, with the name of every
  /// participant. [nameOf] resolves a user id, so the grouping stays free of
  /// the user cache and can be tested on its own.
  static List<MapEntry<String, List<String>>> groupReactions(
      Map<String, String> reactions, String Function(String userId) nameOf) {
    final grouped = <String, List<String>>{};
    for (final entry in reactions.entries) {
      grouped.putIfAbsent(entry.value, () => []).add(nameOf(entry.key));
    }
    final rows = grouped.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.length.compareTo(a.value.length);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return rows;
  }

  /// Who reacted with what. Names come from the local user cache, so this is a
  /// cache read and never a server call.
  static Future<void> showReactions(BuildContext context,
      PrivateMessage message, String conversationUserId) async {
    final reactions = message.reactions ?? const <String, String>{};
    if (reactions.isEmpty) {
      return;
    }
    final me = Singleton().profile.user.id;
    final names = <String, String>{me: 'meText'.tr()};
    for (final id in reactions.keys) {
      if (names.containsKey(id)) {
        continue;
      }
      names[id] = (await CacheUtils.getUserById(id))?.username ?? '?';
    }
    if (!context.mounted) {
      return;
    }
    final rows = groupReactions(reactions, (id) => names[id] ?? '?');

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            // The list is also where a reaction is given: tapping the badge
            // used to open the action sheet, and a read-only list would take
            // that away.
            if (message.id?.isNotEmpty ?? false)
              reactionRow(ctx, message, conversationUserId),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('reactionsTitle'.tr(),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final row in rows)
              ListTile(
                leading: Text(row.key, style: const TextStyle(fontSize: 22)),
                title: Text(row.value.join(', ')),
              ),
          ],
        ),
      ),
    );
  }

  /// Bubble long-press sheet with all actions that apply to [message].
  /// [conversationUserId] is the other side of the conversation.
  static Future<void> showSheet(
      BuildContext context, PrivateMessage message, String conversationUserId,
      {VoidCallback? onDeleted, bool pinned = false, VoidCallback? onSelect}) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final canAddress =
            message.id?.isNotEmpty ?? false; // needs the archive id
        return SafeArea(
          child: Wrap(
            children: [
              // Reactions first: one tap, and the same emoji again removes it.
              if (canAddress) reactionRow(ctx, message, conversationUserId),
              if (message.isMe && !message.isUndecryptable && canAddress)
                ListTile(
                  leading: const Icon(editIcon),
                  title: Text('editMessage'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    edit(context, message, conversationUserId);
                  },
                ),
              if (canAddress)
                ListTile(
                  leading: Icon(pinned ? unpinIcon : pinIcon),
                  title: Text(pinned ? 'unpinMessage'.tr() : 'pinMessage'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    togglePin(message, conversationUserId, pinned: pinned);
                  },
                ),
              if (onSelect != null)
                ListTile(
                  leading: const Icon(selectIcon),
                  title: Text('selectMessage'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelect();
                  },
                ),
              if (message.isMe && message.sendStatus == SendStatus.failed)
                ListTile(
                  leading: const Icon(resendIcon),
                  title: Text('resendMessage'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    ChatSender.resend(conversationUserId, message);
                  },
                ),
              if (message.message.isNotEmpty)
                ListTile(
                  leading: const Icon(copyIcon),
                  title: Text('copyMessage'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    copy(message);
                  },
                ),
              if (canForward(message))
                ListTile(
                  leading: const Icon(forwardIcon),
                  title: Text('forwardMessage'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    forward(context, [message]);
                  },
                ),
              if (canSave(message))
                ListTile(
                  leading: const Icon(saveIcon),
                  title: Text('saveAttachment'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    save(message);
                  },
                ),
              // In the debug self-chat the other side is you, so "for
              // everyone" would mean exactly the same as "for me".
              if (message.isMe &&
                  conversationUserId != Singleton().profile.user.id &&
                  (message.id?.isNotEmpty ?? false))
                ListTile(
                  leading: const Icon(deleteIcon),
                  title: Text('deleteMessageForEveryone'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    deleteForEveryone(context, message, conversationUserId,
                        onDeleted: onDeleted);
                  },
                ),
              ListTile(
                leading: const Icon(deleteIcon),
                title: Text('deleteMessageForMe'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  delete(context, message, conversationUserId,
                      onDeleted: onDeleted);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Copy the message text (the caption for media messages).
  static Future<void> copy(PrivateMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.message));
    Fluttertoast.showToast(msg: 'copiedText'.tr());
  }

  /// Sets the caller's reaction, or removes it when the same emoji is picked
  /// again. The emoji travels encrypted like the message body.
  static Future<void> react(
      PrivateMessage message, String conversationUserId, String emoji) async {
    final id = message.id;
    if (id == null || id.isEmpty) {
      return;
    }
    final me = Singleton().profile.user.id;
    final removing = message.reactions?[me] == emoji;
    try {
      if (removing) {
        await Utils.callApi(() => Singleton().messagesApi.removeReaction(id),
            rethrowErr: true);
      } else {
        final peer = await CacheUtils.getUserById(conversationUserId);
        if (peer == null) {
          return;
        }
        final data = await CryptoUtils.encryptMessageData(
            Uint8List.fromList(utf8.encode(emoji)),
            bu.CryptoUtils.rsaPublicKeyFromPem(peer.publicKey));
        await Utils.callApi(
            () => Singleton().messagesApi.setReaction(
                  id,
                  setReactionInput: SetReactionInput(
                    content: data['encryptedData']!,
                    key: data['encryptedKey']!,
                    nonce: data['nonce']!,
                    mac: data['mac']!,
                  ),
                ),
            rethrowErr: true);
      }
      await CacheUtils.setMessageReaction(
          conversationUserId, message.sentAt, me, removing ? null : emoji);
      MessageNotifier().notify();
    } catch (_) {
      // The server refused; nothing changed locally either.
    }
  }

  /// Pins or unpins the message for both participants.
  static Future<void> togglePin(
      PrivateMessage message, String conversationUserId,
      {required bool pinned}) async {
    final id = message.id;
    if (id == null || id.isEmpty) {
      return;
    }
    try {
      await Utils.callApi(
          () => pinned
              ? Singleton().messagesApi.unpinMessage(id)
              : Singleton().messagesApi.pinMessage(id),
          rethrowErr: true);
      await CacheUtils.setMessagePinned(
          conversationUserId, id, pinned ? null : DateTime.now());
      MessageNotifier().notify();
    } catch (_) {
      // Left as it was.
    }
  }

  /// Rewrites the text of an own message: new ciphertext, server stamp, same
  /// bubble.
  static Future<void> edit(BuildContext context, PrivateMessage message,
      String conversationUserId) async {
    final id = message.id;
    if (id == null || id.isEmpty) {
      return;
    }
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditMessageDialog(initial: message.message),
    );
    // A plain message cannot become empty; a caption can be cleared.
    final unchanged = text == null || text == message.message;
    if (unchanged || (text.trim().isEmpty && !message.isMedia)) {
      return;
    }
    try {
      final peer = await CacheUtils.getUserById(conversationUserId);
      if (peer == null) {
        return;
      }
      // A reply keeps its quote and an attachment keeps its media reference, so
      // only the body of the envelope changes.
      final Uint8List plaintext;
      if (message.isMedia) {
        final references = await ChatSender.mediaReferencesFor(peer, message);
        if (references == null || references.isEmpty) {
          await Fluttertoast.showToast(
              msg: 'attachmentCaptionUneditable'.tr(),
              backgroundColor: Colors.red);
          return;
        }
        plaintext = message.isAlbum
            ? MediaUtils.buildAlbumEnvelope(references, text,
                forwarded: message.forwarded)
            : MediaUtils.buildMediaEnvelope(references.first, text,
                forwarded: message.forwarded);
      } else {
        final reply = message.replyTo;
        plaintext =
            reply == null ? utf8.encode(text) : buildTextEnvelope(text, reply);
      }
      final data = await CryptoUtils.encryptMessageData(
          plaintext, bu.CryptoUtils.rsaPublicKeyFromPem(peer.publicKey));
      final response = await Utils.callApi(
          () => Singleton().messagesApi.editMessage(
                id,
                editMessageInput: EditMessageInput(
                  content: data['encryptedData']!,
                  key: data['encryptedKey']!,
                  nonce: data['nonce']!,
                  mac: data['mac']!,
                ),
              ),
          rethrowErr: true);
      await CacheUtils.markMessageEdited(conversationUserId, message.sentAt,
          text, (response?.editedAt ?? DateTime.now()).toLocal());
      MessageNotifier().notify();
    } catch (_) {
      // The old text stays in place.
    }
  }

  /// Save the decrypted attachment wherever the user picks.
  static Future<void> save(PrivateMessage message) async {
    final path = message.localPath;
    final type = message.mediaType;
    if (path == null || type == null) {
      return;
    }
    try {
      final bytes = await MediaUtils.decryptAtRest(path);
      final saved = await FilePicker.saveFile(
        dialogTitle: 'saveAttachment'.tr(),
        fileName: message.fileName ??
            'whisper_${message.sentAt.millisecondsSinceEpoch}${MediaUtils.extensionForType(type)}',
        bytes: bytes,
      );
      if (saved == null) {
        return;
      }
      Fluttertoast.showToast(msg: 'attachmentSaved'.tr());
    } catch (_) {
      Fluttertoast.showToast(
          msg: 'attachmentSaveFailed'.tr(), backgroundColor: Colors.red);
    }
  }

  /// Pick a chat (or a user) and send the messages there.
  static Future<void> forward(
      BuildContext context, List<PrivateMessage> messages) async {
    await Navigator.of(context).push(stepRoute(ForwardPage(messages)));
  }

  /// Delete the message for this account on every device, after a
  /// confirmation. The other side keeps its copy.
  static void delete(
      BuildContext context, PrivateMessage message, String conversationUserId,
      {VoidCallback? onDeleted}) {
    DialogUtils.yesNoDialog(
        context,
        'deleteMessageConfirm'.tr(),
        'deleteMessageConfirmText'.tr(),
        () => _delete(context, message, conversationUserId,
            forEveryone: false, onDeleted: onDeleted));
  }

  /// Delete an own message for everyone, after a confirmation: the server
  /// erases the ciphertext, so the other side loses it from the archive.
  static void deleteForEveryone(
      BuildContext context, PrivateMessage message, String conversationUserId,
      {VoidCallback? onDeleted}) {
    DialogUtils.yesNoDialog(
        context,
        'deleteMessageForEveryoneConfirm'.tr(),
        'deleteMessageForEveryoneConfirmText'.tr(),
        () => _delete(context, message, conversationUserId,
            forEveryone: true, onDeleted: onDeleted));
  }

  /// Removes [message] on the server first, then locally. A failed server call
  /// leaves the message alone: a local delete on its own would come back with
  /// the next history page.
  static Future<void> _delete(
      BuildContext context, PrivateMessage message, String conversationUserId,
      {required bool forEveryone, VoidCallback? onDeleted}) async {
    // A message that never reached the archive has nothing to delete on the
    // server; only this device holds it.
    final id = message.id;
    if (id != null && id.isNotEmpty) {
      try {
        await Utils.callApi(
            () => forEveryone
                ? Singleton().messagesApi.deleteMessage(id)
                : Singleton().messagesApi.hideMessage(id),
            rethrowErr: true);
      } catch (_) {
        return;
      }
    } else if (forEveryone) {
      await Fluttertoast.showToast(
          msg: 'deleteMessageForEveryoneFailed'.tr(),
          backgroundColor: Colors.red);
      return;
    }
    await CacheUtils.deletePrivateMessage(conversationUserId, message);
    MessageNotifier().notify();
    onDeleted?.call();
  }
}

/// Edit dialog that owns its controller.
///
/// Disposing a controller right after `showDialog` returns races the route's
/// exit animation: the `TextField` is still mounted and the dialog's inherited
/// elements deactivate with a live dependent, which trips
/// `InheritedElement.debugDeactivated` on a phone.
class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initial});

  final String initial;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('editMessage'.tr()),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        minLines: 1,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text('okText'.tr()),
        ),
      ],
    );
  }
}
