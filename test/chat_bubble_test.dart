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
import 'package:whisper/widgets/media_bubble.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

/// Plain text of everything the bubble rendered, spans included.
String renderedText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((widget) => widget.text.toPlainText())
    .join('\n');

/// Style of the span that renders exactly [text], null when it is not there.
TextStyle? spanStyle(WidgetTester tester, String text) {
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    TextStyle? found;
    widget.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) {
        found = span.style;
        return false;
      }
      return true;
    });
    if (found != null) {
      return found;
    }
  }
  return null;
}

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

    // Double tap adds the quick reaction instead of quoting.
    var reacted = false;
    var replied = false;
    await show(ChatBubble(
      null,
      PrivateMessage('2', 'ahoj', DateTime(2026), DateTime(2026), true),
      null,
      peer,
      accentColor: Colors.blue,
      onReply: () => replied = true,
      onQuickReact: () => reacted = true,
    ));
    await tester.tap(find.text('ahoj'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('ahoj'));
    await tester.pumpAndSettle();
    expect(reacted, isTrue);
    expect(replied, isFalse);

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

    // A forwarded message says so above its body.
    await show(ChatBubble(
      null,
      PrivateMessage(
          '2', 'přeposlaný text', DateTime(2026), DateTime(2026), true)
        ..forwarded = true,
      null,
      peer,
      accentColor: Colors.blue,
    ));
    expect(find.text('Forwarded'), findsOneWidget);
    expect(renderedText(tester), contains('přeposlaný text'));

    // Only the peer's cursor covering the message shows a tick; there is no
    // single "delivered" tick any more.
    final sent = DateTime(2026, 11, 19, 12);
    await show(ChatBubble(
      null,
      PrivateMessage('1', 'odesláno', sent, sent, true),
      null,
      peer,
      accentColor: Colors.blue,
    ));
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);

    await show(ChatBubble(
      null,
      PrivateMessage('1', 'přečteno', sent, sent, true),
      null,
      peer,
      accentColor: Colors.blue,
      readAt: sent,
    ));
    expect(find.byIcon(Icons.done_all), findsOneWidget);

    // Reactions are one badge hanging on the bubble's bottom edge: no gap
    // between the emoji and none between the badge and the bubble.
    final sentAt = DateTime(2026, 11, 19, 12);
    var reactionsOpened = 0;
    var actionsOpened = 0;
    await show(ChatBubble(
      null,
      PrivateMessage('1', 'reaguj', sentAt, sentAt, true)
        ..reactions = {'1': '❤️', '2': '😂'},
      null,
      peer,
      accentColor: Colors.blue,
      onActions: () => actionsOpened++,
      onReactions: () => reactionsOpened++,
    ));
    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('😂'), findsOneWidget);
    final body = tester.getRect(find.text('reaguj'));
    final heart = tester.getRect(find.text('❤️'));
    final laugh = tester.getRect(find.text('😂'));
    // Overlapping the bubble instead of sitting below it.
    expect(heart.top, lessThan(body.bottom + 5));
    // The two emoji are one badge, not two chips with a gap.
    expect(laugh.left - heart.right, lessThan(8));
    // Tapping the badge asks who reacted, not for the action sheet.
    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();
    expect(reactionsOpened, 1);
    expect(actionsOpened, 0);

    // Phone numbers and e-mails are underlined like a link.
    await show(ChatBubble(
      null,
      PrivateMessage('2', 'volej +420 123 456 789 nebo piš na jan@example.com',
          DateTime(2026), DateTime(2026), true),
      null,
      peer,
      accentColor: Colors.blue,
    ));
    for (final tappable in ['+420 123 456 789', 'jan@example.com']) {
      final style = spanStyle(tester, tappable);
      expect(style, isNotNull, reason: tappable);
      expect(style!.decoration, TextDecoration.underline, reason: tappable);
      expect(style.decorationStyle ?? TextDecorationStyle.solid,
          TextDecorationStyle.solid,
          reason: tappable);
    }

    // An attachment is the bubble: no coloured frame or padding around it.
    await show(ChatBubble(
      null,
      PrivateMessage(
        '2',
        '',
        DateTime(2026),
        DateTime(2026),
        true,
        mediaTypeStr: MediaType.image.name,
        downloadStatus: MediaDownloadStatus.failed,
      ),
      null,
      peer,
      accentColor: Colors.blue,
    ));
    final mediaFrame = tester.widget<Container>(find
        .ancestor(
            of: find.byType(MediaBubble), matching: find.byType(Container))
        .first);
    expect(mediaFrame.padding, EdgeInsets.zero);
    expect((mediaFrame.decoration as BoxDecoration?)?.color, isNull);

    // A voice message shows the reaction it carries: the badge sits inside the
    // bubble's edge, so a quick react there is not a silent no-op.
    var mediaReactions = 0;
    await show(ChatBubble(
      null,
      PrivateMessage('2', '', DateTime(2026), DateTime(2026), true,
          mediaTypeStr: MediaType.voice.name,
          downloadStatus: MediaDownloadStatus.failed)
        ..reactions = {'2': '👍'},
      null,
      peer,
      accentColor: Colors.blue,
      onReactions: () => mediaReactions++,
    ));
    expect(find.text('👍'), findsOneWidget);
    // The badge on a media bubble is tappable too: it used to hang outside its
    // parent's bounds, which paints but never hits.
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(mediaReactions, 1);

    // A jump lights the target bubble and drops the frame again afterwards.
    Future<Decoration?> frame(ChatBubble bubble) async {
      await show(bubble);
      return tester
          .widget<AnimatedContainer>(find
              .ancestor(
                  of: find.text('cíl'),
                  matching: find.byType(AnimatedContainer))
              .first)
          .foregroundDecoration;
    }

    ChatBubble target({required bool highlight, bool selected = false}) =>
        ChatBubble(
          null,
          PrivateMessage('2', 'cíl', DateTime(2026), DateTime(2026), true),
          null,
          peer,
          accentColor: Colors.blue,
          highlight: highlight,
          selected: selected,
        );
    expect(await frame(target(highlight: false)), isNull);
    expect(await frame(target(highlight: true)), isNotNull);
    expect(await frame(target(highlight: true, selected: true)), isNotNull);
  });
}
