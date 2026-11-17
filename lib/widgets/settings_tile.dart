import 'package:flutter/material.dart';

/// One settings-style row with a fixed height, so rows look the same whether
/// they end in a switch, a badge or nothing.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.trailing,
    this.extra,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Widget at the right edge, e.g. a switch.
  final Widget? trailing;

  /// Widget right after the label, e.g. a colour dot.
  final Widget? extra;

  /// Tint for icon and label; inherited from the button theme when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: color),
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Text(label, style: TextStyle(color: color)),
          ),
          if (extra != null) extra!,
          if (trailing != null) const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
