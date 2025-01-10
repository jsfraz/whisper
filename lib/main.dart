import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import '../utils/cache_utils.dart';
import 'models/app_theme.dart';
import 'models/profile.dart';
import 'models/user.dart';
import 'pages/whisper_page.dart';
import 'utils/singleton.dart';
import 'utils/theme_notifier.dart';
import 'utils/utils.dart';

void main() async {
  // Initialize Flutter widgets
  WidgetsFlutterBinding.ensureInitialized();
  // Load locale
  await EasyLocalization.ensureInitialized();
  // Lock orientation (https://stackoverflow.com/a/52720581/19371130)
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Hive adapters
  Hive
    ..init(await Utils.getCacheDir())
    ..registerAdapter(ProfileAdapter())
    ..registerAdapter(UserAdapter())
    ..registerAdapter(AppThemeAdapter());

  // Default theme
  Singleton().appTheme = await CacheUtils.getTheme() ??
      AppTheme.fromValues(ThemeMode.system, Colors.blue, true);
  // Save theme
  await CacheUtils.setTheme(Singleton().appTheme);

  // App
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('cs')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: ChangeNotifierProvider<ThemeNotifier>(
        create: (context) => ThemeNotifier(Singleton().appTheme),
        child: const WhisperPage(),
      ),
    ),
  );
}
