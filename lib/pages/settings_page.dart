import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:sprintf/sprintf.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/biometric_auth.dart';
import '../utils/cache_utils.dart';
import '../utils/singleton.dart';
import '../utils/dialog_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/utils.dart';
import 'scan_invite_button_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isBiometryEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _isBiometryEnabled = await CacheUtils.isBiometryEnabled();
    setState(() {});
  }

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
        child: Column(
          children: [
            // Theme
            TextButton(
              onPressed: () {
                showDialog(context: context, builder: DialogUtils.themeDialog);
              },
              child: Row(
                children: [
                  Icon(
                    Icons.palette,
                    size: 24,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      'themeSettings'.tr(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                ],
              ),
            ),
            // Notifications
            TextButton(
              onPressed: null,
              child: Row(
                children: [
                  Icon(
                    Icons.notifications,
                    size: 24,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      'notificationSettings'.tr(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                  Spacer(),
                  Switch(
                    value: Singleton().profile.enableNotifications,
                    onChanged: (value) async {
                      setState(() {
                        Singleton().profile.enableNotifications =
                            !Singleton().profile.enableNotifications;
                      });
                      await Singleton().profile.save();
                    },
                  )
                ],
              ),
            ),

            Divider(thickness: 1, indent: 10, endIndent: 10),

            // Biometric authentication
            TextButton(
              onPressed: null,
              child: Row(
                children: [
                  Icon(
                    Icons.fingerprint,
                    size: 24,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      'biometrySettings'.tr(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                  Spacer(),
                  Switch(
                    value: _isBiometryEnabled,
                    onChanged: _toggleBiometry,
                  )
                ],
              ),
            ),

            Divider(thickness: 1, indent: 10, endIndent: 10),

            // How it works
            TextButton(
              onPressed: () async {
                var url = Uri.parse('https://github.com/jsfraz/whisper/wiki');
                if (!await launchUrl(url)) {
                  await Fluttertoast.showToast(
                      msg: sprintf('urlError'.tr(), [url.toString()]),
                      backgroundColor: Colors.red);
                }
              },
              child: Row(
                children: [
                  Icon(
                    Icons.help,
                    size: 24,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      'wikiLink'.tr(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                  ),
                ],
              ),
            ),

            // Repo
            TextButton(
              onPressed: () async {
                var url = Uri.parse('https://github.com/jsfraz/whisper');
                if (!await launchUrl(url)) {
                  await Fluttertoast.showToast(
                      msg: sprintf('urlError'.tr(), [url.toString()]),
                      backgroundColor: Colors.red);
                }
              },
              child: Row(
                children: [
                  Icon(
                    Icons.code,
                    size: 24,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      'repoLink'.tr(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                  ),
                ],
              ),
            ),

            Divider(thickness: 1, indent: 10, endIndent: 10),

            // TODO change password

            // Divider(thickness: 1, indent: 10, endIndent: 10),

            // Danger zone title
            Padding(
              padding: EdgeInsets.only(bottom: 5),
              child: Text(
                'dangerZone'.tr(),
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),

            // Delete all chats
            TextButton(
              onPressed: () async {
                await DialogUtils.yesNoDialog(
                    context,
                    'deleteAllChatsConfirm'.tr(),
                    'deleteAllChatsConfirmText'.tr(), () async {
                  MessageNotifier().deleteAllChats();
                  Navigator.pop(context);
                });
              },
              child: Row(
                children: [
                  Icon(
                    Icons.delete_forever,
                    size: 24,
                    color: Colors.red,
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      'deleteAllChats'.tr(),
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                  ),
                ],
              ),
            ),

            // Logout (delete account)
            TextButton(
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
                          context,
                          MaterialPageRoute(
                              builder: (context) => ScanInviteButtonPage()));
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
              child: Row(
                children: [
                  Icon(
                    Icons.logout,
                    size: 24,
                    color: Colors.red,
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      'logoutAndDelete'.tr(),
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
