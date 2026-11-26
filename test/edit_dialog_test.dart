import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// easy_localization reads the locale from shared_preferences, its transitive dep
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/models/profile.dart';
import 'package:shept/models/user.dart';
import 'package:shept/utils/message_actions.dart';
import 'package:shept/utils/singleton.dart';

/// Closing the edit dialog used to dispose its controller while the route was
/// still animating out; that trips `InheritedElement.debugDeactivated` on a
/// device (red screen after a successful edit). The dialog now owns its
/// controller, and this test locks the close path in.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Singleton().profile =
        Profile('', User('1', 'me', '', false), '', '', '', '', false);
  });

  testWidgets('the edit dialog opens and closes without a framework assert',
      (tester) async {
    final message =
        PrivateMessage('1', 'hello', DateTime(2026), DateTime(2026), true)
          ..id = '00000000-0000-4000-8000-000000000000';

    await tester.pumpWidget(EasyLocalization(
      path: 'assets/translations',
      supportedLocales: const [Locale('en'), Locale('cs')],
      fallbackLocale: const Locale('en'),
      child: Builder(builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Scaffold(
            body: Center(
              child: Builder(builder: (inner) {
                return ElevatedButton(
                  onPressed: () => MessageActions.edit(inner, message, '5'),
                  child: const Text('edit'),
                );
              }),
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit message'), findsOneWidget);

    // Typing then cancelling is the same teardown path as confirming.
    await tester.enterText(find.byType(TextField), 'hello again');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit message'), findsNothing);
  });
}
