import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/dialog_utils.dart';

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
}
