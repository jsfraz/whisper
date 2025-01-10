import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:whisper/utils/dialog_utils.dart';

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
                  SizedBox(
                    width: 24,
                  ),
                ],
              ),
            ),
            Divider(thickness: 1),

            // TODO change password

            // Divider(thickness: 1),

            // TODO delete account (logout)

            // TODO space

            // TODO how it works
            // TODO repo
          ],
        ),
      ),
    );
  }
}
