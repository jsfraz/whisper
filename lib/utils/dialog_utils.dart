import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../utils/cache_utils.dart';
import 'package:whisper_openapi_client/api.dart';
import 'singleton.dart';
import 'theme_notifier.dart';
import 'utils.dart';

class DialogUtils {
  /// Returns invite dialog
  static Widget inviteDialog(BuildContext context) {
    final TextEditingController controllerMail = TextEditingController();
    bool mailOk = false;
    bool mailEditing = false;

    String? errorMail() {
      if (!EmailValidator.validate(controllerMail.text) && mailEditing) {
        return 'invalidMail'.tr();
      }
      if (EmailValidator.validate(controllerMail.text)) {
        mailOk = true;
      }
      return null;
    }

    /// Creates invite
    Future<void> createInvite() async {
      if (mailOk) {
        await Utils.callApi(
            () => Singleton().inviteApi.createInvite(
                createInviteInput:
                    CreateInviteInput(mail: controllerMail.text)),
            true);
        if (context.mounted) {
          Navigator.pop(context);
        }
      }
    }

    return StatefulBuilder(builder: (context, setState) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          title: Text('newInvite'.tr()),
          content: SizedBox(
            width: MediaQuery.of(context).size.width / 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controllerMail,
                  onChanged: (_) => setState(() {
                    mailEditing = true;
                  }),
                  decoration: InputDecoration(
                      errorText: errorMail(), hintText: 'userMail'.tr()),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            TextButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.primary),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(35)),
                ),
              ),
              onPressed: createInvite,
              child: Text(
                'newInvite'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.surface),
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Returns theme dialog
  static Widget themeDialog(BuildContext context) {
    /// Change theme via notifier
    changeTheme() {
      Provider.of<ThemeNotifier>(context, listen: false)
          .changeTheme(Singleton().appTheme);
    }

    return StatefulBuilder(builder: (context, setState) {
      /// Open color picker dialog/// Open color picker dialog
      Future openColorPickerDialog() async {
        await showDialog(
                context: context,
                builder: (context) =>
                    colorPickerDialog(context, Singleton().appTheme.color))
            .then((value) async {
          if (value != null) {
            setState(() {
              Singleton().appTheme.color = value;
              changeTheme();
            });
            await CacheUtils.setTheme(Singleton().appTheme);
          }
        });
      }

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          title: Text('themeSettings'.tr()),
          content: SizedBox(
            width: MediaQuery.of(context).size.width / 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Theme mode
                Row(
                  children: [
                    Text(
                      'themeMode'.tr(),
                      style: TextStyle(fontSize: 16),
                    ),
                    Spacer(),
                    DropdownButton(
                      value: Singleton().appTheme.themeMode,
                      items: ThemeMode.values.map((ThemeMode mode) {
                        return DropdownMenuItem(
                          value: mode,
                          child: Text('${mode.name}Text'),
                        );
                      }).toList(),
                      onChanged: (ThemeMode? value) async {
                        setState(() {
                          Singleton().appTheme.themeMode = value!;
                          changeTheme();
                        });
                        await CacheUtils.setTheme(Singleton().appTheme);
                      },
                    )
                  ],
                ),
                // Theme color
                Row(
                  children: [
                    Text(
                      'themeColor'.tr(),
                      style: TextStyle(fontSize: 16),
                    ),
                    Spacer(),
                    ElevatedButton(
                      onPressed: openColorPickerDialog,
                      child: Text('chooseColor'),
                    ),
                  ],
                ),
                // Use material 3
                Row(
                  children: [
                    Text(
                      'useMat3'.tr(),
                      style: TextStyle(fontSize: 16),
                    ),
                    Spacer(),
                    Switch(
                        value: Singleton().appTheme.useMaterial3,
                        onChanged: (_) {
                          setState(() {
                            Singleton().appTheme.useMaterial3 =
                                !Singleton().appTheme.useMaterial3;
                            changeTheme();
                            CacheUtils.setTheme(Singleton().appTheme);
                          });
                        })
                  ],
                )
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            TextButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.primary),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(35)),
                ),
              ),
              onPressed: Navigator.of(context).pop,
              child: Text(
                'okText'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.surface),
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Returns color picker dialog
  static Widget colorPickerDialog(BuildContext context, Color initialColor) {
    Color pickerColor = initialColor;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AlertDialog(
        title: Text('pickColor'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorPicker(
              enableAlpha: false,
              labelTypes: [],
              pickerColor: initialColor,
              onColorChanged: (color) => pickerColor = color,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(pickerColor),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.primary),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
              ),
            ),
            child: Text('okText'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.surface)),
          ),
        ],
      ),
    );
  }
}
