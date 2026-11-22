import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/widgets/attachment_confirm_sheet.dart';
// easy_localization reads the locale from shared_preferences, its transitive dep
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    // easy_localization reads the locale from shared_preferences
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  // One app for the whole test: easy_localization loads its bundle once, and a
  // second pumpWidget would leave the tree without translations.
  testWidgets('the sheet returns the caption and the view-once choice',
      (tester) async {
    AttachmentConfirmResult? result;
    await tester.pumpWidget(EasyLocalization(
      path: 'assets/translations',
      supportedLocales: const [Locale('en'), Locale('cs')],
      fallbackLocale: const Locale('en'),
      child: Builder(builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Builder(
            builder: (inner) => Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      result = await AttachmentConfirmSheet.show(inner,
                          count: 2, initialCaption: 'draft');
                    },
                    child: const Text('album'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      result = await AttachmentConfirmSheet.show(inner,
                          count: 1, allowViewOnce: true);
                    },
                    child: const Text('single'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      result = await AttachmentConfirmSheet.show(inner,
                          count: 1, allowViewOnce: false);
                    },
                    child: const Text('plain'),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    ));
    // Let easy_localization load the bundle before interacting.
    await tester.pumpAndSettle();

    // Cancel
    await tester.tap(find.text('album'));
    await tester.pumpAndSettle();
    expect(find.text('draft'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result, isNull);

    // Send: the exit animation keeps rebuilding the sheet, which used to touch
    // a controller that had already been disposed.
    await tester.tap(find.text('album'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result!.caption, 'draft');
    expect(result!.viewOnce, isFalse);

    // One visual attachment can be turned into a single view.
    await tester.tap(find.text('single'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(result!.viewOnce, isTrue);

    // An album or a file is never offered the switch.
    await tester.tap(find.text('plain'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
  });
}
