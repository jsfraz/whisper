import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// intl is pinned through easy_localization; declaring it a second time would
// only duplicate that pin.
// ignore: depend_on_referenced_packages
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import '../utils/message_notifier.dart';
import '../utils/cache_utils.dart';
import 'models/app_theme.dart';
import 'models/private_message.dart';
import 'models/profile.dart';
import 'models/user.dart';
import 'pages/shept_page.dart';
import 'utils/media_utils.dart';
import 'utils/storage_utils.dart';
import 'utils/notification_service.dart';
import 'utils/singleton.dart';
import 'utils/theme_notifier.dart';
import 'utils/utils.dart';

void main() async {
  // Initialize Flutter widgets
  WidgetsFlutterBinding.ensureInitialized();

  // MCP toolkit exposes app internals over the debug VM service. Debug only;
  // never use it with a real account (see AGENTS.md).
  if (kDebugMode) {
    try {
      MCPToolkitBinding.instance
        ..initialize()
        ..initializeFlutterToolkit();
    } catch (e) {
      debugPrint('MCP toolkit init failed: $e');
    }
  }

  if (Platform.isAndroid || Platform.isIOS) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // Load locale (the notification service needs it for the channel texts)
  await EasyLocalization.ensureInitialized();
  // Date patterns and month names for the languages the app ships with. Without
  // them DateFormat falls back to English for everything.
  for (final locale in ['en', 'cs']) {
    await initializeDateFormatting(locale);
  }

  // Local notifications. A failure here must not block the app.
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init failed: $e');
  }

  if (Platform.isAndroid || Platform.isIOS) {
    // Lock orientation (https://stackoverflow.com/a/52720581/19371130)
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // Hive adapters
  Hive
    ..init(await Utils.getCacheDir())
    ..registerAdapter(ProfileAdapter())
    ..registerAdapter(UserAdapter())
    ..registerAdapter(AppThemeAdapter())
    ..registerAdapter(PrivateMessageAdapter());

  // Plaintext media from an interrupted playback or send must not survive a
  // restart.
  await MediaUtils.clearTempFiles();

  // A disappearing message that expired while the app was closed is gone
  // before the first frame: it must not flash up on start.
  await CacheUtils.purgeExpiredMessages();

  // Same for attachments the user asked to drop after a while.
  await StorageUtils.purgeIfDue();

  // Default theme
  Singleton().appTheme = await CacheUtils.getTheme() ??
      AppTheme.fromValues(ThemeMode.system, Colors.blue);
  // Save theme
  await CacheUtils.setTheme(Singleton().appTheme);

  // App
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (_) => ThemeNotifier(Singleton().appTheme)),
        ChangeNotifierProvider<MessageNotifier>(
            create: (_) => MessageNotifier())
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('cs')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: SheptPage(),
      ),
    ),
  );
}
