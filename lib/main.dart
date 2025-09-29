import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import '../utils/message_notifier.dart';
import '../utils/cache_utils.dart';
import 'models/app_theme.dart';
import 'models/private_message.dart';
import 'models/profile.dart';
import 'models/user.dart';
import 'pages/whisper_page.dart';
import 'utils/notification_service.dart';
import 'utils/singleton.dart';
import 'utils/theme_notifier.dart';
import 'utils/utils.dart';

// TODO tor?

void main() async {
  // Initialize Flutter widgets
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialization
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Local notifications
  NotificationService().init();

  // Load locale
  await EasyLocalization.ensureInitialized();
  
  // Lock orientation (https://stackoverflow.com/a/52720581/19371130)
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Hive adapters
  Hive
    ..init(await Utils.getCacheDir())
    ..registerAdapter(ProfileAdapter())
    ..registerAdapter(UserAdapter())
    ..registerAdapter(AppThemeAdapter())
    ..registerAdapter(PrivateMessageAdapter());

  // Default theme
  Singleton().appTheme = await CacheUtils.getTheme() ??
      AppTheme.fromValues(ThemeMode.system, Colors.blue, true);
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
        child: WhisperPage(),
      ),
    ),
  );
}
