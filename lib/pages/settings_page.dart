import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settingsPage'.tr()),
      ),
      body: SafeArea(
        child: Column(children: [
          // TODO theme brightness
          // TODO theme color
          // TODO use material3

          // TODO divider

          // TODO change password

          // TODO divider

          // TODO delete account (logout)

          // TODO divider

          // TODO how it works
          // TODO repo
        ],),
      ),
    );
  }
}
