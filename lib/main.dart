import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'models/app_theme.dart';
import 'models/profile.dart';
import 'models/user.dart';
import 'pages/whisper_page.dart';
import 'utils/singleton.dart';
import 'utils/theme_notifier.dart';
import 'utils/utils.dart';

void main() async {
  // Initialize Singleton
  Singleton();
  // Initialize Flutter widgets
  WidgetsFlutterBinding.ensureInitialized();
  // Load locale
  await EasyLocalization.ensureInitialized();

  // Hive adapters
  Hive
    ..init(await Utils.getCacheDir())
    ..registerAdapter(ProfileAdapter())
    ..registerAdapter(UserAdapter());

  // Default theme
  AppTheme defaultTheme = AppTheme(ThemeMode.system, Colors.blue, true);

  // App
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('cs')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: ChangeNotifierProvider<ThemeNotifier>(
        create: (context) => ThemeNotifier(defaultTheme),
        child: const WhisperPage(),
      ),
    ),
  );
}
