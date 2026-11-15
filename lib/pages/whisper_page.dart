import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/page_navigator_observer.dart';
import '../utils/theme_notifier.dart';
import '../pages/scan_invite_button_page.dart';
import 'password_page.dart';
import '../utils/cache_utils.dart';

class WhisperPage extends StatelessWidget {
  const WhisperPage({super.key});

  /// Fade-through everywhere so `MaterialPageRoute` pushes (forward, search,
  /// registration) use the same timing as the rest of the app.
  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(builders: {
    TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
  });

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
      navigatorObservers: [PageNavigatorObserver()],
      debugShowCheckedModeBanner: true,
      // Light theme
      theme: ThemeData.from(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Provider.of<ThemeNotifier>(context).appTheme.color,
                  brightness: Brightness.light),
              useMaterial3:
                  Provider.of<ThemeNotifier>(context).appTheme.useMaterial3)
          .copyWith(pageTransitionsTheme: _pageTransitionsTheme),
      // Dark theme
      darkTheme: ThemeData.from(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Provider.of<ThemeNotifier>(context).appTheme.color,
                  brightness: Brightness.dark),
              useMaterial3:
                  Provider.of<ThemeNotifier>(context).appTheme.useMaterial3)
          .copyWith(pageTransitionsTheme: _pageTransitionsTheme),
      // Light / Dark / System
      themeMode: Provider.of<ThemeNotifier>(context).appTheme.themeMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: FutureBuilder<Widget>(
          future: _getDefaultPage(),
          builder: (context, snapshot) {
            // Loading
            if (snapshot.connectionState != ConnectionState.done) {
              return _getScaffoldCenter(const CircularProgressIndicator());
            }
            // Done
            return snapshot.data!;
          }),
    );
  }
}
