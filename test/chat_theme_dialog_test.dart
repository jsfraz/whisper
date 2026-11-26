import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shept/utils/dialog_utils.dart';
import 'package:shept/widgets/theme_palette.dart';

/// The per-chat dialog shares the app theme's palette, and adds the one choice
/// that only a chat has: fall back to the global color.
void main() {
  testWidgets(
      'the chat dialog hands back the picked color, and null for global',
      (tester) async {
    final calls = <Color?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => DialogUtils.chatThemeDialog(
                      context,
                      current: Colors.blue,
                      onChanged: (color) async => calls.add(color),
                    )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('themeSwatch-8')));
    await tester.pumpAndSettle();
    expect(calls.last?.toARGB32(), Colors.teal.toARGB32());

    // The inherit tile is the chat dialog's own choice: the app theme dialog
    // has no such tile.
    await tester.tap(find.byKey(const ValueKey('themeSwatch-global')));
    await tester.pumpAndSettle();
    expect(calls.last, isNull);
  });

  testWidgets('a swatch repaints the sample before the dialog is confirmed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => DialogUtils.chatThemeDialog(
                      context,
                      current: null,
                      onChanged: (_) async {},
                    )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Nothing picked yet: the sample follows the global theme.
    expect(tester.widget<ThemePreview>(find.byType(ThemePreview)).seed, isNull);

    final swatch = find.byKey(const ValueKey('themeSwatch-8'));
    await tester.ensureVisible(swatch);
    await tester.pumpAndSettle();
    await tester.tap(swatch);
    await tester.pumpAndSettle();

    // A rebuild used to reset the pick to the value the page had on open, so
    // the preview only moved once the dialog was confirmed.
    expect(
        tester.widget<ThemePreview>(find.byType(ThemePreview)).seed?.toARGB32(),
        Colors.teal.toARGB32());
  });
}
