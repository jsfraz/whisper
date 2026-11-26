import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// easy_localization reads the locale from shared_preferences, its transitive dep
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shept/widgets/typing_dots.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Widget app(Widget child, {bool reduceMotion = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('typing is three animated dots', (tester) async {
    await tester.pumpWidget(app(const TypingDots()));
    await tester.pump();
    // Three circles, no text hint.
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle),
        findsNWidgets(3));
  });

  testWidgets('reduced motion gets a static ellipsis instead', (tester) async {
    await tester.pumpWidget(app(const TypingDots(), reduceMotion: true));
    await tester.pump();
    expect(find.text('…'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle),
        findsNothing);
  });
}
