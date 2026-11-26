import 'dart:convert';

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
import 'package:shept/utils/text_envelope.dart';
import 'package:shept/widgets/chat_bubble.dart';
import 'package:shept/widgets/view_once_frame.dart';

void main() {
  final peer = User('2', 'peer', '', false);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Singleton().profile =
        Profile('', User('1', 'me', '', false), '', '', '', '', false);
  });

  PrivateMessage location({bool mine = false, DateTime? openedAt}) {
    final at = DateTime(2026);
    return PrivateMessage(
      mine ? '1' : '2',
      '',
      at,
      at,
      true,
      viewOnce: true,
      openedAt: openedAt,
      locationJson: jsonEncode(const LocationRef(50.08, 14.42).toJson()),
    );
  }

  Widget app(PrivateMessage message) => EasyLocalization(
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
      );

  // One app for the whole test: easy_localization loads its bundle once.
  testWidgets('a view-once location is a card revealed once', (tester) async {
    await tester.pumpWidget(app(location()));
    await tester.pumpAndSettle();

    // The recipient gets the placeholder, and it is tappable.
    expect(find.text('Tap to view once'), findsOneWidget);
    expect(tester.widget<ViewOnceFrame>(find.byType(ViewOnceFrame)).onTap,
        isNotNull);
    // The coordinates are not shown before the reveal.
    expect(find.textContaining('50.08'), findsNothing);

    // Once opened it is a tombstone with no way back in.
    await tester.pumpWidget(app(location(openedAt: DateTime(2026, 1, 2))));
    await tester.pumpAndSettle();
    expect(find.text('Opened'), findsOneWidget);
    expect(
        tester.widget<ViewOnceFrame>(find.byType(ViewOnceFrame)).onTap, isNull);

    // The sender never gets the reveal, only the state.
    await tester.pumpWidget(app(location(mine: true)));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ViewOnceFrame>(find.byType(ViewOnceFrame)).onTap, isNull);
    expect(find.byType(ViewOnceFrame), findsOneWidget);
  });
}
