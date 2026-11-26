import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// easy_localization reads the locale from shared_preferences, its transitive dep
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/models/profile.dart';
import 'package:shept/models/user.dart';
import 'package:shept/utils/singleton.dart';
import 'package:shept/widgets/chat_bubble.dart';

void main() {
  final peer = User('2', 'peer', '', false);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Singleton().profile =
        Profile('', User('1', 'me', '', false), '', '', '', '', false);
  });

  // One app for the whole test: easy_localization loads its bundle once.
  testWidgets('the avatar closes a run, unless the caller says otherwise',
      (tester) async {
    final message =
        PrivateMessage('2', 'ahoj', DateTime(2026), DateTime(2026), true);

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
              child: ChatBubble(
                null,
                message,
                null,
                peer,
                accentColor: Colors.blue,
              ),
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsOneWidget);

    // The live-location marker follows, so this message does not close the run.
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
              child: ChatBubble(
                null,
                message,
                null,
                peer,
                accentColor: Colors.blue,
                showAvatar: false,
              ),
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsNothing);
  });
}
