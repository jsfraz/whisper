import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../utils/color_utils.dart';
import '../utils/singleton.dart';
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<HomePage> {
  int currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Get color of user profile picture
    Color userColor =
        ColorUtils.getColorFromUsername(Singleton().profile.user.username);

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
                    color: ColorUtils.getReadableColor(userColor),
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
              onPressed: () async {
                // await Utils.callApi(() => Singleton().userApi.getAllUsers(), true);    // TODO delete
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
              Provider.of<ThemeNotifier>(context, listen: false).changeTheme(
                  AppTheme(
                      ThemeMode.dark,
                      ColorUtils.getMaterialColor(
                          Color((Random().nextDouble() * 0xFFFFFF).toInt())
                              .withValues(alpha: 1.0)),
                      true));
            }); // TODO delete
            */
          },
          shape: const CircleBorder(),
          foregroundColor: Theme.of(context).colorScheme.surface,
          backgroundColor: Theme.of(context).colorScheme.primary,
          tooltip: currentPageIndex == 0
              ? 'addChat'.tr()
              : 'addUser'.tr(), // Change tooltip according to page index
          child: Icon(currentPageIndex == 0
              ? Icons.add_comment
              : Icons.person_add), // Change icon according to page index
        ),
        // Bottom navigation bar for admin only
        bottomNavigationBar: Singleton().profile.user.admin
            ? SizedBox(
                height: 70,
                child: NavigationBar(
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
                ),
              )
            : null,
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
        ][currentPageIndex], // Pick widget by current index
      ),
    );
  }
}
