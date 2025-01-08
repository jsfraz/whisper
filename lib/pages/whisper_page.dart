import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/theme_notifier.dart';
import '../pages/scan_invite_button_page.dart';
import 'password_page.dart';
import '../utils/cache_utils.dart';
import '../utils/no_glow_behavior.dart';

class WhisperPage extends StatelessWidget {
  const WhisperPage({super.key});

  /// Returns default page based on user in cache.
  Future<Widget> _getDefaultPage() async {
    // Set default page
    Widget defaultPage = const ScanInviteButtonPage();

    // Check for password hash in cache
    String? hash = await CacheUtils.getPasswordHash();
    if (hash != null) {
      defaultPage = const PasswordPage();
    }

    return defaultPage;
  }

  /// Returns Scaffold containing SafeArea with centered Widget.
  Scaffold _getScaffoldCenter(Widget widget) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Center(
          child: widget,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: true,
      // Light theme
      theme: ThemeData.from(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Provider.of<ThemeNotifier>(context).appTheme.color,
              brightness: Brightness.light),
          useMaterial3:
              Provider.of<ThemeNotifier>(context).appTheme.useMaterial3),
      // Dark theme
      darkTheme: ThemeData.from(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Provider.of<ThemeNotifier>(context).appTheme.color,
              brightness: Brightness.dark),
          useMaterial3:
              Provider.of<ThemeNotifier>(context).appTheme.useMaterial3),
      // Light / Dark / System
      themeMode: Provider.of<ThemeNotifier>(context).appTheme.themeMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) {
        return ScrollConfiguration(
          behavior: NoGlowBehavior(),
          child: child!,
        );
      },
      home: FutureBuilder<Widget>(
          future: _getDefaultPage(),
          builder: (context, snapshot) {
            // Loading
            if (snapshot.connectionState != ConnectionState.done) {
              return _getScaffoldCenter(const CircularProgressIndicator());
            }
            // Error
            if (snapshot.hasError) {
              return _getScaffoldCenter(Text(
                'fuckedUp'.tr(),
                textAlign: TextAlign.center,
              ));
            }
            // Done
            return snapshot.data!;
          }),
    );
  }
}
