import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:whisper_openapi_client/api.dart';
import '../models/user.dart';
import '../utils/color_utils.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import '../widgets/user_list_item.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<HomePage> {
  List<User> serverUsers = [];
  List<int> selectedUsers = [];
  int currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load all server users if admin
      if (Singleton().profile.user.admin) {
        _getServerUsers();
      }
    });
  }

  /// Get server users
  Future<void> _getServerUsers() async {
    setState(() {
      serverUsers = [];
      selectedUsers = [];
    });
    var users =
        await Utils.callApi(() => Singleton().userApi.getAllUsers(), true);
    setState(() {
      if (users != null) {
        for (var x in users) {
          serverUsers.add(User.fromModel(x));
        }
      }
    });
  }

  /// Delete selected users button
  Future<void> _deleteSelectedUsersButton() async {
    await _deleteSelectedUsersDialog(context);
  }

  /// Delete selected users
  Future<void> _deleteSelectedUsers() async {
    setState(() {
      serverUsers =
          []; // I am unable to deactivate the user checkbox, so I will make all the users vanish so it will reset itself :)
    });
    // Delete selected users
    await Utils.callApi(
        () => Singleton().userApi.deleteUsers(
            deleteUsersInput: DeleteUsersInput(ids: selectedUsers)),
        true);
    setState(() {
      selectedUsers = [];
    });
    // Refresh users
    await _getServerUsers();
  }

  // Show delete users dialog
  Future<void> _deleteSelectedUsersDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('deleteUserConfirm'.tr()),
          content: Text('deleteUserConfirmText'.tr()),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelLarge,
              ),
              child: Text('noText'.tr()),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelLarge,
              ),
              child: Text('yesText'.tr()),
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteSelectedUsers();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get color of user profile picture
    Color userColor =
        ColorUtils.getColorFromUsername(Singleton().profile.user.username);

    return PopScope(
      child: Scaffold(
        appBar: currentPageIndex == 0
            ? AppBar(
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
                      // TODO search
                    },
                  ),
                  // More
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'moreButton'.tr(),
                    onPressed: () {
                      // TODO more
                    },
                  ),
                ],
              )
            : null,
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
                      label: 'adminPage'.tr(),
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
          DefaultTabController(
            initialIndex: 0,
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: Text('adminPage'.tr()),
                bottom: TabBar(
                  tabs: <Widget>[
                    Tab(
                      child: Text(
                        'serverUsersPage'.tr(),
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                    Tab(
                      child: Text(
                        'activeInvitesPage'.tr(),
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
              body: TabBarView(
                children: <Widget>[
                  // Server users
                  Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.all(5),
                          child: ElevatedButton(
                            onPressed: selectedUsers.isEmpty
                                ? null
                                : _deleteSelectedUsersButton,
                            child: Text('deleteUser'.tr()),
                          ),
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _getServerUsers,
                          child: serverUsers.isEmpty
                              ? Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text('noServerUsers'.tr()),
                                )
                              : ListView.builder(
                                  itemCount: serverUsers.length,
                                  itemBuilder: (context, index) {
                                    return UserListItem(serverUsers[index],
                                        (isSelected) {
                                      // Add/remove selected users from list
                                      setState(() {
                                        if (isSelected) {
                                          isSelected = isSelected;
                                          selectedUsers
                                              .add(serverUsers[index].id);
                                        } else {
                                          selectedUsers
                                              .remove(serverUsers[index].id);
                                        }
                                      });
                                    });
                                  },
                                ),
                        ),
                      )
                    ],
                  ),
                  Center(
                    child: Text("This is active invite page."),
                  ),
                ],
              ),
            ),
          )
        ][currentPageIndex], // Pick widget by current index
      ),
    );
  }
}
