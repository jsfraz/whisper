import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// easy_localization reads the locale from shared_preferences, its transitive dep
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shept/models/private_message.dart';
import 'package:shept/pages/chat_media_page.dart';
import 'package:shept/utils/cache_utils.dart';
import 'package:shept_websocket_client_dart/models/media_type.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('shept_chat_media_page');
    Hive.init(dir.path);
    Hive.registerAdapter(PrivateMessageAdapter());
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    await Hive.openBox('privateMessages');
    await Hive.box('privateMessages').clear();
    await Hive.openBox('conversations');
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  Widget app() => EasyLocalization(
        path: 'assets/translations',
        supportedLocales: const [Locale('en'), Locale('cs')],
        fallbackLocale: const Locale('en'),
        child: Builder(builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const ChatMediaPage('peer'),
          );
        }),
      );

  testWidgets('an empty chat says so instead of drawing nothing',
      (tester) async {
    await tester.runAsync(() => tester.pumpWidget(app()));
    await tester.pumpAndSettle();

    expect(find.text('No media in this chat yet'), findsOneWidget);
  });

  testWidgets('a document shows its extension badge', (tester) async {
    final sentAt = DateTime(2026, 11, 20, 12);
    // Hive writes are real file I/O: outside runAsync the fake test clock would
    // wait on them forever.
    await tester.runAsync(() => CacheUtils.addPrivateMessages('peer', [
          PrivateMessage('peer', '', sentAt, sentAt, true,
              localPath: '/tmp/shept_test_report.pdf',
              mediaTypeStr: MediaType.file.name,
              fileName: 'report.pdf'),
        ]));

    await tester.runAsync(() => tester.pumpWidget(app()));
    await tester.pumpAndSettle();

    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('No media in this chat yet'), findsNothing);
  });
}
