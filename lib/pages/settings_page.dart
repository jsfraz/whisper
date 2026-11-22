import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:sprintf/sprintf.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:whisper_openapi_client_dart/api.dart';
import '../utils/biometric_auth.dart';
import '../utils/cache_utils.dart';
import '../utils/singleton.dart';
import '../utils/dialog_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/utils.dart';
import 'scan_invite_button_page.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/settings_tile.dart';
import '../utils/nav_transitions.dart';
import 'devices_page.dart';
import 'storage_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isBiometryEnabled = false;
  bool _notificationPreview = false;
  bool _typingIndicator = false;
  bool _presence = false;

  /// Guards the retention flow: the settings round-trip is slow, and without it
  /// a second tap stacks another dialog on top of the first.
  bool _retentionBusy = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _isBiometryEnabled = await CacheUtils.isBiometryEnabled();
    _notificationPreview = await CacheUtils.getNotificationPreview();
    _typingIndicator = await CacheUtils.isTypingIndicatorEnabled();
    _presence = await CacheUtils.isPresenceEnabled();
    setState(() {});
  }

  /// Server-side retention of the ciphertext archive. The shorter setting of
  /// the two participants wins, so this is a limit, not a promise.
  Future<void> _showRetentionDialog() async {
    if (_retentionBusy) {
      return;
    }
    _retentionBusy = true;
    try {
      // Blocks the page while the request is in flight, so a fast second tap
      // cannot reach the tile and nothing else can be tapped meanwhile.
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      final current =
          await Utils.callApi(() => Singleton().userApi.getRetention());
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      final selected = await showDialog<int>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text('retentionTitle'.tr()),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('retentionExplain'.tr()),
            ),
            for (final days in const [7, 30, 90, 365])
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(days),
                child: Row(
                  children: [
                    Icon(
                      current?.days == days
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: Theme.of(dialogContext).colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text('retentionDays'.tr(args: [days.toString()])),
                  ],
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) {
        return;
      }
      await Utils.callApi(() => Singleton()
          .userApi
          .setRetention(setRetentionInput: SetRetentionInput(days: selected)));
      if (!mounted) {
        return;
      }
      await Fluttertoast.showToast(
          msg: 'retentionSaved'.tr(), backgroundColor: Colors.grey);
    } finally {
      _retentionBusy = false;
    }
  }

  /// Language is stored by easy_localization in SharedPreferences.
  Future<void> _showLanguageDialog() async {
    final selected = await showDialog<Locale>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('languageSettings'.tr()),
        children: [
          for (final locale in context.supportedLocales)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(locale),
              child: Row(
                children: [
                  Icon(
                    context.locale.languageCode == locale.languageCode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: Theme.of(dialogContext).colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Text(_languageNames[locale.languageCode] ??
                      locale.languageCode),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    await context.setLocale(selected);
  }

  static const _languageNames = {'cs': 'Čeština', 'en': 'English'};

  Future<void> _toggleBiometry(bool switchValue) async {
    if (switchValue) {
      // Enable
      final success = await BiometricAuth.storeEncryptionKey(
          Singleton().boxCollectionKey, context);
      if (success) {
        await Fluttertoast.showToast(
            msg: 'biometricsEnabled'.tr(), backgroundColor: Colors.grey);
        setState(() {
          _isBiometryEnabled = true;
        });
      } else {
        await Fluttertoast.showToast(
            msg: 'biometricSetupFailed'.tr(), backgroundColor: Colors.red);
        setState(() {
          _isBiometryEnabled = false;
        });
      }
    } else {
      // Disable
      final success = await BiometricAuth.disableBiometricAuth(context);
      if (success) {
        await Fluttertoast.showToast(
            msg: 'biometricsDisabled'.tr(), backgroundColor: Colors.grey);
        setState(() {
          _isBiometryEnabled = false;
        });
      } else {
        await Fluttertoast.showToast(
            msg: 'biometricSetupFailed'.tr(), backgroundColor: Colors.red);
        setState(() {
          _isBiometryEnabled = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settingsPage'.tr()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _settingsTile(
                icon: Icons.palette,
                label: 'themeSettings'.tr(),
                onPressed: () => showDialog(
                    context: context, builder: DialogUtils.themeDialog),
              ),
              _settingsTile(
                icon: Icons.language,
                label: 'languageSettings'.tr(),
                onPressed: _showLanguageDialog,
              ),
              _settingsTile(
                icon: Icons.notifications,
                label: 'notificationSettings'.tr(),
                trailing: Switch(
                  value: Singleton().profile.enableNotifications,
                  onChanged: (value) async {
                    setState(() {
                      Singleton().profile.enableNotifications =
                          !Singleton().profile.enableNotifications;
                    });
                    await Singleton().profile.save();
                  },
                ),
              ),
              _settingsTile(
                icon: Icons.visibility,
                label: 'notificationPreview'.tr(),
                trailing: Switch(
                  value: _notificationPreview,
                  onChanged: (value) async {
                    setState(() {
                      _notificationPreview = !_notificationPreview;
                    });
                    await CacheUtils.setNotificationPreview(
                        _notificationPreview);
                  },
                ),
              ),
              // Both live-metadata switches are off by default: with them off
              // no frame is ever sent and the server learns nothing.
              _settingsTile(
                icon: Icons.edit_notifications,
                label: 'typingIndicator'.tr(),
                trailing: Switch(
                  value: _typingIndicator,
                  onChanged: (value) async {
                    setState(() {
                      _typingIndicator = !_typingIndicator;
                    });
                    await CacheUtils.setTypingIndicatorEnabled(
                        _typingIndicator);
                  },
                ),
              ),
              _settingsTile(
                icon: Icons.circle,
                label: 'presence'.tr(),
                trailing: Switch(
                  value: _presence,
                  onChanged: (value) async {
                    setState(() {
                      _presence = !_presence;
                    });
                    await CacheUtils.setPresenceEnabled(_presence);
                    // Turning it on announces right away; turning it off tells
                    // the peers, so nobody keeps a stale "online".
                    if (_presence) {
                      await Utils.announcePresence();
                    } else {
                      await Utils.withdrawPresence();
                    }
                  },
                ),
              ),
              const Divider(thickness: 1, indent: 10, endIndent: 10),
              _settingsTile(
                icon: Icons.fingerprint,
                label: 'biometrySettings'.tr(),
                trailing: Switch(
                  value: _isBiometryEnabled,
                  onChanged: _toggleBiometry,
                ),
              ),
              _settingsTile(
                icon: Icons.devices,
                label: 'devicesSettings'.tr(),
                onPressed: () async {
                  await Navigator.push(context, stepRoute(const DevicesPage()));
                },
              ),
              _settingsTile(
                icon: Icons.storage,
                label: 'storageTitle'.tr(),
                onPressed: () async {
                  await Navigator.push(context, stepRoute(const StoragePage()));
                },
              ),
              _settingsTile(
                icon: Icons.archive,
                label: 'retentionSettings'.tr(),
                onPressed: _showRetentionDialog,
              ),
              const Divider(thickness: 1, indent: 10, endIndent: 10),
              _settingsTile(
                icon: Icons.help,
                label: 'wikiLink'.tr(),
                onPressed: () =>
                    _openUrl('https://github.com/jsfraz/whisper/wiki'),
              ),
              _settingsTile(
                icon: Icons.code,
                label: 'repoLink'.tr(),
                onPressed: () => _openUrl('https://github.com/jsfraz/whisper'),
              ),
              const Divider(thickness: 1, indent: 10, endIndent: 10),
              _settingsTile(
                icon: Icons.password,
                label: 'changePassword'.tr(),
                onPressed: () async {
                  final changed = await showDialog<bool>(
                      context: context,
                      builder: (context) => const ChangePasswordDialog());
                  if (changed == true) {
                    await Fluttertoast.showToast(msg: 'passwordChanged'.tr());
                  }
                },
              ),
              const Divider(thickness: 1, indent: 10, endIndent: 10),
              _settingsTile(
                icon: Icons.delete_forever,
                label: 'deleteAllChats'.tr(),
                color: Colors.red,
                onPressed: () async {
                  await DialogUtils.yesNoDialog(
                      context,
                      'deleteAllChatsConfirm'.tr(),
                      'deleteAllChatsConfirmText'.tr(), () async {
                    MessageNotifier().deleteAllChats();
                    Navigator.pop(context);
                  });
                },
              ),
              _settingsTile(
                icon: Icons.logout,
                label: 'logoutAndDelete'.tr(),
                color: Colors.red,
                onPressed: () async {
                  await DialogUtils.yesNoDialog(
                      context, 'logoutConfirm'.tr(), 'logoutConfirmText'.tr(),
                      () async {
                    // Delete everything and close app
                    try {
                      await Utils.callApi(() => Singleton().userApi.deleteMe());
                      await CacheUtils.deleteCache();
                      await Fluttertoast.showToast(
                          msg: 'accountDeleted1'.tr(),
                          backgroundColor: Colors.grey);
                      if (Platform.isIOS) {
                        // Apple (https://stackoverflow.com/a/57534684/19371130)
                        Navigator.pushReplacement(
                            context, fadeRoute(ScanInviteButtonPage()));
                      } else if (Platform.isAndroid) {
                        // Android
                        SystemNavigator.pop();
                      }
                    } catch (e) {
                      await Fluttertoast.showToast(
                          msg: e.toString(), backgroundColor: Colors.red);
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One settings row in the app's accent colour.
  Widget _settingsTile({
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    Widget? trailing,
    Color? color,
  }) {
    return SettingsTile(
      icon: icon,
      label: label,
      onPressed: onPressed,
      trailing: trailing,
      color: color ?? Theme.of(context).colorScheme.secondary,
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      await Fluttertoast.showToast(
          msg: sprintf('urlError'.tr(), [uri.toString()]),
          backgroundColor: Colors.red);
    }
  }
}
