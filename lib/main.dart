import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'pages/whisper_page.dart';
import 'utils/singleton.dart';

void main() async {
  // Initialize Singleton
  Singleton();
  // Initialize Flutter widgets
  WidgetsFlutterBinding.ensureInitialized();
  // Load locale
  await EasyLocalization.ensureInitialized();
  /*
  Directory dir = await getApplicationDocumentsDirectory();
  Hive
    // folder path
    ..init('${dir.path}/TextM')
    // adapters
    ..registerAdapter(ProfileAdapter())
    ..registerAdapter(UserAdapter());
  */

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('cs')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const WhisperPage(),
    ),
  );
}
