import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../models/private_message.dart';
import '../pages/forward_page.dart';
import 'cache_utils.dart';
import 'dialog_utils.dart';
import 'media_utils.dart';
import 'message_notifier.dart';

/// Actions for a single message, offered by the bubble long-press sheet and by
/// the attachment viewer's overflow menu.
class MessageActions {
  /// Whether [message] can be saved or forwarded (the file must be on disk).
  static bool canSave(PrivateMessage message) =>
      message.isMedia && message.localPath != null;

  /// Bubble long-press sheet with all actions that apply to [message].
  /// [conversationUserId] is the other side of the conversation.
  static Future<void> showSheet(
      BuildContext context, PrivateMessage message, int conversationUserId,
      {VoidCallback? onDeleted}) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              if (message.message.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text('copyMessage'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    copy(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: Text('forwardMessage'.tr()),
                onTap: () {
                  Navigator.pop(ctx);
                  forward(context, message);
                },
              ),
              if (canSave(message))
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text('saveAttachment'.tr()),
                  onTap: () {
                    Navigator.pop(ctx);
                    save(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete),
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
        fileName:
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

  /// Pick a chat (or a user) and send the message there.
  static Future<void> forward(
      BuildContext context, PrivateMessage message) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ForwardPage(message)));
  }

  /// Delete the message only on this device, after a confirmation.
  static void delete(
      BuildContext context, PrivateMessage message, int conversationUserId,
      {VoidCallback? onDeleted}) {
    DialogUtils.yesNoDialog(
        context, 'deleteMessageConfirm'.tr(), 'deleteMessageConfirmText'.tr(),
        () async {
      await CacheUtils.deletePrivateMessage(conversationUserId, message);
      MessageNotifier().notify();
      onDeleted?.call();
    });
  }
}
