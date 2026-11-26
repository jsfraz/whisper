import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../utils/cache_utils.dart';
import 'package:shept_openapi_client_dart/api.dart';
import '../widgets/theme_palette.dart';
import 'color_utils.dart';
import 'singleton.dart';
import 'theme_notifier.dart';
import 'utils.dart';

class DialogUtils {
  /// Returns invite dialog
  static Widget inviteDialog(BuildContext context) {
    final TextEditingController controllerMail = TextEditingController();
    bool mailOk = false;
    bool mailEditing = false;
    bool creating = false;

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
        creating = true;
        await Utils.callApi(() => Singleton().inviteApi.createInvite(
            createInviteInput: CreateInviteInput(mail: controllerMail.text)));
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
              onPressed: creating ? null : createInvite,
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
    void changeTheme() {
      Provider.of<ThemeNotifier>(context, listen: false)
          .changeTheme(Singleton().appTheme);
    }

    /// Applies a change live: the preview and the page behind the dialog move
    /// with it, so there is no apply button to forget.
    Future<void> apply(VoidCallback mutate) async {
      mutate();
      changeTheme();
      await CacheUtils.setTheme(Singleton().appTheme);
    }

    return StatefulBuilder(builder: (context, setState) {
      /// Open the color wheel; the palette covers the common cases.
      Future openColorPickerDialog() async {
        final value = await showDialog<Color>(
            context: context,
            builder: (context) =>
                colorPickerDialog(context, Singleton().appTheme.color));
        if (value != null) {
          setState(() {
            Singleton().appTheme.color = value;
          });
          await apply(() {});
        }
      }

      final theme = Singleton().appTheme;
      final seed = theme.color;

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          // The dialog had a quarter of the screen; a seed palette and a
          // preview need the width, and 380 keeps it readable on a tablet.
          constraints: const BoxConstraints(maxWidth: 380),
          title: Text('themeSettings'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThemePreview(seed: seed),
                  const SizedBox(height: 16),
                  Center(
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: [
                        for (final mode in ThemeMode.values)
                          ButtonSegment<ThemeMode>(
                            value: mode,
                            icon: Icon(
                              switch (mode) {
                                ThemeMode.system => Icons.brightness_auto,
                                ThemeMode.light => Icons.light_mode,
                                ThemeMode.dark => Icons.dark_mode,
                              },
                              // The icons carry the label for the screen reader;
                              // three labels would not fit next to each other.
                              semanticLabel: '${mode.name}Text'.tr(),
                            ),
                          ),
                      ],
                      selected: {theme.themeMode},
                      onSelectionChanged: (selection) async {
                        setState(() {
                          theme.themeMode = selection.first;
                        });
                        await apply(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('themeColor'.tr(),
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  ThemePalette(
                    selected: seed,
                    onPicked: (color) async {
                      setState(() {
                        theme.color = color;
                      });
                      await apply(() {});
                    },
                    onCustom: openColorPickerDialog,
                  ),
                ],
              ),
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
                style:
                    TextStyle(color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Returns the per-chat theme dialog: the same palette and preview as the app
  /// theme, plus a tile that hands the chat back to the global color. Mode and
  /// Material version stay global, so they are not offered here.
  ///
  /// [onChanged] receives the picked color, or null for "use the global theme",
  /// and is awaited before the next tap, so the page can persist it.
  static Widget chatThemeDialog(
    BuildContext context, {
    required Color? current,
    required Future<void> Function(Color? color) onChanged,
  }) {
    // Outside the builder: a rebuild must not reset the pick back to the value
    // the page had when the dialog opened.
    Color? picked = current;
    return StatefulBuilder(builder: (context, setState) {
      Future openColorPickerDialog() async {
        final value = await showDialog<Color>(
            context: context,
            builder: (context) => colorPickerDialog(
                context, picked ?? Singleton().appTheme.color));
        if (value != null) {
          setState(() {
            picked = value;
          });
          await onChanged(value);
        }
      }

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          constraints: const BoxConstraints(maxWidth: 380),
          title: Text('chatTheme'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThemePreview(seed: picked),
                  const SizedBox(height: 20),
                  Text('themeColor'.tr(),
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  ThemePalette(
                    selected: picked,
                    inheritSelected: picked == null,
                    onInherit: () async {
                      setState(() {
                        picked = null;
                      });
                      await onChanged(null);
                    },
                    onPicked: (color) async {
                      setState(() {
                        picked = color;
                      });
                      await onChanged(color);
                    },
                    onCustom: openColorPickerDialog,
                  ),
                ],
              ),
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
              child: Text('okText'.tr(),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary)),
            ),
          ],
        ),
      );
    });
  }

  /// Returns color picker dialog
  static Widget colorPickerDialog(BuildContext context, Color initialColor) {
    Color pickerColor = initialColor;
    String hexOf(Color color) => '#'
        '${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final hexController = TextEditingController(text: hexOf(initialColor));

    return StatefulBuilder(builder: (context, setState) {
      void pick(Color color) {
        setState(() {
          pickerColor = color;
          hexController.text = hexOf(color);
        });
      }

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          constraints: const BoxConstraints(maxWidth: 380),
          title: Text('pickColor'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // What the wheel currently holds, before the hex field: the
                  // wheel alone does not say which color is selected.
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: pickerColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hexController,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '#RRGGBB',
                      prefixIcon: Icon(Icons.tag, size: 18),
                    ),
                    onChanged: (value) {
                      try {
                        final parsed = ColorUtils.colorFromHex(value);
                        setState(() {
                          pickerColor = parsed;
                        });
                      } catch (_) {
                        // Half-typed hex: keep the last valid color.
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  ColorPicker(
                    enableAlpha: false,
                    labelTypes: const [],
                    displayThumbColor: true,
                    pickerColor: pickerColor,
                    onColorChanged: pick,
                  ),
                ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(pickerColor),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.primary),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(35)),
                ),
              ),
              child: Text('okText'.tr(),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary)),
            ),
          ],
        ),
      );
    });
  }

  /// Returns yes/no dialog. [theme] carries the chat colour when the dialog is
  /// opened from a chat, whose Theme does not reach the Navigator's overlay.
  static Future<void> yesNoDialog(
      BuildContext context, String title, String content, Function onYes,
      {ThemeData? theme}) {
    return showDialog(
      context: context,
      builder: (dialogContext) {
        final dialog = BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            title: Text(title),
            content: Text(content),
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
                child: Text(
                  'yesText'.tr(),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.surface),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onYes();
                },
              ),
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
                  'noText'.tr(),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.surface),
                ),
              ),
            ],
          ),
        );
        return theme == null ? dialog : Theme(data: theme, child: dialog);
      },
    );
  }
}
