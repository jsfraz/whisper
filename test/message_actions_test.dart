import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// easy_localization reads the locale from shared_preferences, its transitive dep
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/utils/message_actions.dart';

void main() {
  setUpAll(() async {
    // easy_localization reads the locale from shared_preferences
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('the sheet offers only the actions that apply', (tester) async {
    // Swapped between the two steps; the app is built once so the localization
    // asset is loaded only once.
    var message =
        PrivateMessage('2', 'hello', DateTime(2026), DateTime(2026), true);

    await tester.pumpWidget(EasyLocalization(
      path: 'assets/translations',
      supportedLocales: const [Locale('en'), Locale('cs')],
      fallbackLocale: const Locale('en'),
      child: Builder(builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Builder(builder: (inner) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => MessageActions.showSheet(inner, message, '5'),
                  child: const Text('open'),
                ),
              ),
            );
          }),
        );
      }),
    ));
    await tester.pumpAndSettle();

    // Text message: copy, forward, delete. Nothing to save.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Forward'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Save attachment'), findsNothing);

    // Close the sheet
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Attachment on disk without a caption: save, forward, delete, no copy.
    message = PrivateMessage('2', '', DateTime(2026), DateTime(2026), true,
        localPath: '/tmp/whisper_media_test', mediaTypeStr: 'image');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Save attachment'), findsOneWidget);
    expect(find.text('Forward'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
  });
}
