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

  testWidgets('cancel returns null and send returns the caption', (tester) async {
    String? result = 'unset';
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
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await AttachmentConfirmSheet.show(inner,
                        count: 2, initialCaption: 'draft');
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
      }),
    ));
    // Let easy_localization load the bundle before interacting.
    await tester.pumpAndSettle();

    // Cancel
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('draft'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result, isNull);

    // Send: the exit animation keeps rebuilding the sheet, which used to touch
    // a controller that had already been disposed.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result, 'draft');
  });
}
