import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../utils/singleton.dart';
import 'dart:math';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<HomePage> {
  int currentPageIndex = 0;

  Color _getColorFromUsername(String username) {
    // Hash username
    int hash = username.hashCode;
    // Get RGB values from hash
    int red = (hash & 0xFF0000) >> 16; // Upper 8 bits
    int green = (hash & 0x00FF00) >> 8; // Middle 8 bits
    int blue = (hash & 0x0000FF); // Bottom 8 bits
    // Get color
    int minBrightness = 100;
    red = max(red, minBrightness);
    green = max(green, minBrightness);
    blue = max(blue, minBrightness);
    return Color.fromARGB(255, red, green, blue);
  }

  Color _getReadableColor(Color backgroundColor) {
    // Převod ARGB na HSV
    final hsvColor = HSVColor.fromColor(backgroundColor);

    // Nastavení minimální světlosti
    const double minBrightness = 0.3; // Barva nebude tmavší než 30 %

    // Zvýšení nebo snížení světlosti (value) pro kontrast
    double adjustedValue = hsvColor.value < 0.5
        ? (hsvColor.value + 0.5).clamp(0.0, 1.0)
        : (hsvColor.value - 0.5).clamp(0.0, 1.0);

    // Zajištění, že světlost neklesne pod minimální jas
    adjustedValue =
        adjustedValue < minBrightness ? minBrightness : adjustedValue;

    // Snížení sytosti pro jemnější kontrast
    final double adjustedSaturation = hsvColor.saturation * 0.7;

    // Vytvoření nové barvy s upravenou světlostí a sytostí
    final newHsvColor =
        hsvColor.withSaturation(adjustedSaturation).withValue(adjustedValue);

    return newHsvColor.toColor();
  }

  @override
  Widget build(BuildContext context) {
    Color userColor = _getColorFromUsername(Singleton().profile.user.username);

    return PopScope(
      child: Scaffold(
        appBar: AppBar(
          // User icon with first letter
          leading: Transform.scale(
            scale: 0.65,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: userColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  Singleton().profile.user.username.isNotEmpty
                      ? Singleton().profile.user.username[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: _getReadableColor(userColor),
                    fontSize: 30,
                  ),
                ),
              ),
            ),
          ),
          // Title
          title: Text('msgPage'.tr()),
          // Action buttons
          actions: [
            // Search
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'searchButton'.tr(),
              onPressed: () {
                setState(() {
                  // TODO search
                });
              },
            ),
            // More
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'moreButton'.tr(),
              onPressed: () {
                setState(() {
                  // TODO more
                });
              },
            ),
          ],
        ),
        resizeToAvoidBottomInset: false,
        // Floating button
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // TODO add
            /*
            setState(() {
              Provider.of<ThemeNotifier>(context, listen: false).changeTheme(AppTheme(ThemeMode.dark, Colors.deepPurple, true));
            });
            */
          },
          shape: const CircleBorder(),
          tooltip: currentPageIndex == 0 ? 'addChat'.tr() : 'addUser'.tr(),    // Change tooltip according to page index
          foregroundColor: Theme.of(context).colorScheme.surface,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(currentPageIndex == 0 ? Icons.add_comment : Icons.person_add),   // Change icon according to page index
        ),
        // Bottom navigation bar for admin only
        bottomNavigationBar: Singleton().profile.user.admin ? NavigationBar(
          onDestinationSelected: (int index) {
            setState(() {
              currentPageIndex = index;
            });
          },
          selectedIndex: currentPageIndex,
          destinations: <Widget>[
            // Messages
            NavigationDestination(
              icon: const Icon(Icons.chat),
              label: 'msgPage'.tr(),
            ),
            // Admin panel
            NavigationDestination(
              icon: const Icon(Icons.admin_panel_settings),
              label: 'adminPanel'.tr(),
            ),
          ],
        ) : null,
        // Body
        body: <Widget>[
          // Messages
          SafeArea(
            child: Center(
              child: Text(
                  'Hello ${Singleton().profile.user.username}! This is message page.'),
            ),
          ),
          // Admin panel
          SafeArea(
            child: Center(
              child: Text(
                  'Hello ${Singleton().profile.user.username}! This is admin panel.'),
            ),
          ),
        ][currentPageIndex],  // Pick widget by current index
      ),
    );
  }
}
