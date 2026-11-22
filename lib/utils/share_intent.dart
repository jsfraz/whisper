import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/user.dart';
import '../pages/chat_page.dart';
import 'app_navigator.dart';
import 'cache_utils.dart';
import 'chat_sender.dart';
import 'media_utils.dart';

/// Receives pictures, videos and files shared from other apps.
///
/// The picked chat decides where the files go; nothing is sent before the user
/// picks one, so a share into the app cannot become a message to the wrong
/// person.
class SharedInbox {
  SharedInbox._();

  /// How many shared files one message may carry.
  static const int maxFiles = 10;

  /// Starts listening for inbound shares: once for a cold start, and then for
  /// every share while the app runs.
  static Future<void> start() async {
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        ReceiveSharingIntent.instance.reset();
        await _offer(initial);
      }
      ReceiveSharingIntent.instance.getMediaStream().listen((shared) {
        if (shared.isNotEmpty) {
          _offer(shared);
        }
      });
    } catch (_) {
      // A platform without share intents simply has no inbox.
    }
  }

  static Future<void> _offer(List<SharedMediaFile> shared) async {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    final users = await CacheUtils.getAllUsers();
    if (users.isEmpty) {
      return;
    }
    final target = await showModalBottomSheet<User>(
      context: navigator.context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('shareToChat'.tr(),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final user in users)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: user.avatarColor,
                  child: Text(user.username.isEmpty
                      ? '?'
                      : user.username[0].toUpperCase()),
                ),
                title: Text(user.username),
                onTap: () => Navigator.pop(ctx, user),
              ),
          ],
        ),
      ),
    );
    if (target == null) {
      return;
    }
    await _send(target, shared.take(maxFiles).toList());
  }

  static Future<void> _send(User target, List<SharedMediaFile> shared) async {
    try {
      if (shared.length == 1) {
        final file = File(shared.single.path);
        final bytes = await file.readAsBytes();
        if (!MediaUtils.uploadFits(bytes.length)) {
          throw Exception('fileTooLarge'.tr());
        }
        await ChatSender.sendMedia(
            target, MediaUtils.detectType(file.path), bytes,
            fileName: MediaUtils.baseName(file.path));
      } else {
        final attachments = <OutgoingAttachment>[];
        for (final item in shared) {
          final file = File(item.path);
          final bytes = await file.readAsBytes();
          if (!MediaUtils.uploadFits(bytes.length)) {
            continue;
          }
          attachments.add(OutgoingAttachment(
            type: MediaUtils.detectType(file.path),
            bytes: bytes,
            fileName: MediaUtils.baseName(file.path),
          ));
        }
        if (attachments.isEmpty) {
          throw Exception('fileTooLarge'.tr());
        }
        await ChatSender.sendAlbum(target, attachments);
      }
      appNavigatorKey.currentState
          ?.push(MaterialPageRoute(builder: (_) => ChatPage(target)));
    } catch (e) {
      await Fluttertoast.showToast(
          msg: e.toString(), backgroundColor: Colors.red);
    }
  }
}
