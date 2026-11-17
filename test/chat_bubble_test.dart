import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// easy_localization reads the locale from shared_preferences, its transitive dep
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper/models/profile.dart';
import 'package:whisper/models/user.dart';
import 'package:whisper/utils/singleton.dart';
import 'package:whisper/utils/text_envelope.dart';
import 'package:whisper/widgets/chat_bubble.dart';

/// Plain text of everything the bubble rendered, spans included.
String renderedText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((widget) => widget.text.toPlainText())
    .join('\n');

void main() {
  final peer = User('2', 'peer', '', false);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    // isMe compares against the signed-in user.
    Singleton().profile =
        Profile('', User('1', 'me', '', false), '', '', '', '', false);
  });

  testWidgets('the bubble renders, quotes, selects and replies',
      (tester) async {
    // One app for the whole test: easy_localization loads its asset once, and a
    // second pumpWidget would leave the tree without translations.
    final shown = ValueNotifier<Widget>(const SizedBox());
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
              child: ValueListenableBuilder<Widget>(
                valueListenable: shown,
                builder: (_, child, __) => child,
              ),
            ),
          ),
        );
      }),
    ));

    Future<void> show(Widget child) async {
      shown.value = child;
      await tester.pumpAndSettle();
    }

    // Formatting: the markers never reach the screen.
    await show(ChatBubble(
      null,
      PrivateMessage(
          '2', 'the **bold** part', DateTime(2026), DateTime(2026), true),
      null,
      peer,
      accentColor: Colors.blue,
    ));
    expect(renderedText(tester), contains('the bold part'));
    expect(renderedText(tester), isNot(contains('**')));

    // A reply shows what it quotes, and tapping the quote jumps to it.
    var jumped = false;
    await show(ChatBubble(
      null,
      PrivateMessage('2', 'souhlas', DateTime(2026), DateTime(2026), true)
        ..setReplyTo(ReplyRef(
          senderId: '1',
          sentAt: DateTime(2025),
          preview: 'původní dotaz',
        )),
      null,
      peer,
      accentColor: Colors.blue,
      onTapQuote: () => jumped = true,
    ));
    expect(renderedText(tester), contains('původní dotaz'));
    expect(renderedText(tester), contains('souhlas'));
    await tester.tap(find.text('původní dotaz'));
    await tester.pumpAndSettle();
    expect(jumped, isTrue);

    // Selection mode marks the bubble.
    await show(ChatBubble(
      null,
      PrivateMessage('2', 'x', DateTime(2026), DateTime(2026), true),
      null,
      peer,
      accentColor: Colors.blue,
      selectionMode: true,
      selected: true,
    ));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Double tap quotes the message in the composer.
    var replied = false;
    await show(ChatBubble(
      null,
      PrivateMessage('2', 'ahoj', DateTime(2026), DateTime(2026), true),
      null,
      peer,
      accentColor: Colors.blue,
      onReply: () => replied = true,
    ));
    await tester.tap(find.text('ahoj'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('ahoj'));
    await tester.pumpAndSettle();
    expect(replied, isTrue);

    // A long message can be unfolded.
    await show(ChatBubble(
      null,
      PrivateMessage('2', 'x' * 700, DateTime(2026), DateTime(2026), true),
      null,
      peer,
      accentColor: Colors.blue,
    ));
    expect(find.text('Show full message'), findsOneWidget);
    await tester.tap(find.text('Show full message'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
  });
}
