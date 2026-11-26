import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shept/models/app_theme.dart';
import 'package:shept/utils/dialog_utils.dart';
import 'package:shept/utils/singleton.dart';
import 'package:shept/utils/theme_notifier.dart';

/// The theme dialog applies on tap, so picking a swatch has to move the seed
/// the whole app is seeded with - and show which one is in use.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_theme_dialog_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppThemeAdapter());
    }
  });

  setUp(() async {
    await Hive.openBox('theme');
    await Hive.box('theme').clear();
    Singleton().appTheme = AppTheme.fromValues(ThemeMode.system, Colors.blue);
  });

  tearDownAll(() async {
    await dir.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    final theme = ThemeNotifier(Singleton().appTheme);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
      value: theme,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog(
                  context: context, builder: DialogUtils.themeDialog),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a swatch becomes the seed and is marked as picked',
      (tester) async {
    await open(tester);
    expect(find.byIcon(Icons.check), findsOneWidget, reason: 'blue is picked');

    await tester.tap(find.byKey(const ValueKey('themeSwatch-8')));
    await tester.pumpAndSettle();
    // Let the fire-and-forget Hive write finish before the test tears down.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));

    // getMaterialColor builds a fresh MaterialColor, so compare values.
    expect(Singleton().appTheme.color.toARGB32(), Colors.teal.toARGB32());
    // The check has to move to the picked swatch: comparing the stored
    // MaterialColor by identity left it on the custom tile forever.
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('themeSwatch-8')),
          matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    final swatch = tester.widget<Container>(find
        .descendant(
            of: find.byKey(const ValueKey('themeSwatch-8')),
            matching: find.byType(Container))
        .first);
    expect((swatch.decoration as BoxDecoration?)?.color?.toARGB32(),
        Colors.teal.toARGB32());
  });
}
