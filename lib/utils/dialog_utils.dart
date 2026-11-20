import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../utils/cache_utils.dart';
import 'package:whisper_openapi_client_dart/api.dart';
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

  /// Seed colors offered as swatches in the theme dialog.
  static const List<MaterialColor> themeSeeds = [
    Colors.blue,
    Colors.indigo,
    Colors.deepPurple,
    Colors.pink,
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.cyan,
    Colors.brown,
    Colors.blueGrey,
  ];

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
      final inPalette = themeSeeds.any((color) => color == seed);

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
                  _themePreview(context, seed),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < themeSeeds.length; i++)
                        _colorSwatch(
                          context,
                          key: ValueKey('themeSwatch-$i'),
                          color: themeSeeds[i],
                          selected: themeSeeds[i] == seed,
                          onTap: () async {
                            setState(() {
                              theme.color = themeSeeds[i];
                            });
                            await apply(() {});
                          },
                        ),
                      // The custom color is a tile of its own: a hand picked
                      // seed is not in the palette, and it still has to show as
                      // the current choice.
                      _colorSwatch(
                        context,
                        key: const ValueKey('themeSwatch-custom'),
                        color: inPalette ? null : seed,
                        selected: !inPalette,
                        icon: inPalette ? Icons.colorize : null,
                        onTap: openColorPickerDialog,
                      ),
                    ],
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

  /// Live sample of the theme: what the picked seed and mode look like on a
  /// bubble, on the surface and on a filled button.
  static Widget _themePreview(BuildContext context, Color seed) {
    final scheme = ColorScheme.fromSeed(
        seedColor: seed, brightness: Theme.of(context).brightness);
    Widget bubble(String text, {required bool mine}) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mine ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            style: TextStyle(
                fontSize: 13,
                color: mine ? scheme.onPrimary : scheme.onSurface),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bubble('themePreviewPeer'.tr(), mine: false),
          const SizedBox(height: 6),
          bubble('themePreviewOwn'.tr(), mine: true),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () {},
            child: Text('themePreviewButton'.tr()),
          ),
        ],
      ),
    );
  }

  /// One round seed swatch of the theme palette, with a check when it is the
  /// one in use.
  static Widget _colorSwatch(
    BuildContext context, {
    required Key key,
    required Color? color,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: key,
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: color == null ? scheme.outline : scheme.outlineVariant,
          ),
        ),
        child: Icon(
          selected ? Icons.check : icon,
          size: 20,
          color: color == null
              ? scheme.onSurfaceVariant
              : ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                  ? Colors.white
                  : Colors.black,
        ),
      ),
    );
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

  /// Returns yes/no dialog
  static Future<void> yesNoDialog(
      BuildContext context, String title, String content, Function onYes) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
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
      },
    );
  }
}
