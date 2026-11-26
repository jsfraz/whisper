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
import 'package:shept/widgets/media_bubble.dart';

void main() {
  final peer = User('2', 'peer', '', false);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Singleton().profile =
        Profile('', User('1', 'me', '', false), '', '', '', '', false);
  });

  testWidgets('a deleted message keeps its place as a tombstone', (
    tester,
  ) async {
    await tester.pumpWidget(EasyLocalization(
      path: 'assets/translations',
      supportedLocales: const [Locale('en'), Locale('cs')],
      fallbackLocale: const Locale('en'),
      child: Builder(builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Center(
              child: ChatBubble(
                null,
                PrivateMessage('2', '', DateTime(2026), DateTime(2026), true)
                  ..deletedAt = DateTime(2026)
                  ..mediaTypeStr = 'image',
                null,
                peer,
                accentColor: Colors.blue,
              ),
            ),
          ),
        );
      }),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Message deleted'), findsOneWidget);
    // The attachment is gone with the content.
    expect(find.byType(MediaBubble), findsNothing);
  });
}
