import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Seed colors offered as swatches: the app theme and the per-chat theme draw
/// from the same list, so a color picked in one place exists in the other.
const List<MaterialColor> themeSeeds = [
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

/// Whether [color] is one of [themeSeeds]. Compared by value: a stored theme
/// rebuilds its MaterialColor, so identity never matches.
bool isSeedColor(Color? color) {
  if (color == null) {
    return false;
  }
  return themeSeeds.any((seed) => seed.toARGB32() == color.toARGB32());
}

/// Live sample of a theme: a bubble of each side and a filled button.
///
/// [seed] is the color the sample is tinted with, the global app color when
/// null.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.seed});

  final Color? seed;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed ?? Theme.of(context).colorScheme.primary,
      brightness: Theme.of(context).brightness,
    );

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
              color: mine ? scheme.onPrimary : scheme.onSurface,
            ),
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
}

/// Round seed swatches with the controls that sit next to them in a theme
/// dialog: a custom color and, when a chat may inherit, the global one.
class ThemePalette extends StatelessWidget {
  const ThemePalette({
    super.key,
    required this.selected,
    this.onPicked,
    this.onCustom,
    this.onInherit,
    this.inheritSelected = false,
  });

  /// The seed in use, null when the theme inherits the global color.
  final Color? selected;

  final ValueChanged<Color>? onPicked;
  final VoidCallback? onCustom;

  /// Present when "use the global theme" is a choice of its own.
  final VoidCallback? onInherit;
  final bool inheritSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onInherit != null)
          _Swatch(
            key: const ValueKey('themeSwatch-global'),
            color: null,
            selected: inheritSelected,
            icon: Icons.public,
            tooltip: 'useGlobalTheme'.tr(),
            onTap: onInherit,
          ),
        for (var i = 0; i < themeSeeds.length; i++)
          _Swatch(
            key: ValueKey('themeSwatch-$i'),
            color: themeSeeds[i],
            selected: selected?.toARGB32() == themeSeeds[i].toARGB32(),
            onTap: onPicked == null ? null : () => onPicked!(themeSeeds[i]),
          ),
        // A hand picked color is not in the palette, and it still has to show
        // as the current choice.
        _Swatch(
          key: const ValueKey('themeSwatch-custom'),
          color: isSeedColor(selected) ? null : selected,
          selected: selected != null && !isSeedColor(selected),
          icon:
              isSeedColor(selected) || selected == null ? Icons.colorize : null,
          onTap: onCustom,
        ),
      ],
    );
  }
}

/// One round swatch, with a check when it is the one in use.
class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    this.icon,
    this.tooltip,
    this.onTap,
  });

  final Color? color;
  final bool selected;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = selected ? Icons.check : icon;
    final widget = InkWell(
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
        child: mark == null
            ? null
            : Icon(
                mark,
                size: 20,
                color: color == null
                    ? scheme.onSurfaceVariant
                    : ThemeData.estimateBrightnessForColor(color!) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
              ),
      ),
    );
    if (tooltip == null) {
      return widget;
    }
    return Tooltip(message: tooltip!, child: widget);
  }
}
