import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'models/profile.dart';
import 'models/user.dart';
import 'pages/whisper_page.dart';
import 'utils/singleton.dart';
import 'utils/utils.dart';

void main() async {
  // Initialize Singleton
  Singleton();
  // Initialize Flutter widgets
  WidgetsFlutterBinding.ensureInitialized();
  // Load locale
  await EasyLocalization.ensureInitialized();
  
  Hive
    // Adapters
    ..init(await Utils.getCacheDir())
    ..registerAdapter(ProfileAdapter())
    ..registerAdapter(UserAdapter());

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('cs')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const WhisperPage(),
    ),
  );
}
