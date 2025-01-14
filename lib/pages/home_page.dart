import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';
import '../utils/test_utils.dart';
import 'search_user_page.dart';
import 'settings_page.dart';
import '../utils/dialog_utils.dart';
import '../widgets/invite_list_item.dart';
import 'package:whisper_openapi_client_dart/api.dart';
import '../models/user.dart';
import '../utils/color_utils.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import '../widgets/select_user_list_item.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<User> _serverUsers = [];
  List<int> _selectedUsers = [];
  int _currentPageIndex = 0;
  List<ModelsInvite> _serverInvites = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load all server users and invites if admin
      if (Singleton().profile.user.admin) {
        _getServerUsers();
        _getServerInvites();
      }
    });
  }

  /// Get server users
  Future<void> _getServerUsers() async {
    if (mounted) {
      setState(() {
        _serverUsers = [];
        _selectedUsers = [];
      });
      var users =
          await Utils.callApi(() => Singleton().userApi.getAllUsers(), true);
      if (mounted) {
        setState(() {
          if (users != null) {
            for (var x in users) {
              _serverUsers.add(User.fromModel(x));
            }
          }
        });
      }
    }
  }

  /// Delete selected users button
  Future<void> _deleteSelectedUsersButton() async {
    await _deleteSelectedUsersDialog(context);
  }

  /// Delete selected users
  Future<void> _deleteSelectedUsers() async {
    setState(() {
      _serverUsers =
          []; // I am unable to deactivate the user checkbox, so I will make all the users vanish so it will reset itself :)
    });
    // Delete selected users
    await Utils.callApi(
        () => Singleton().userApi.deleteUsers(
            deleteUsersInput: DeleteUsersInput(ids: _selectedUsers)),
        true);
    setState(() {
      _selectedUsers = [];
    });
    // Refresh users
    await _getServerUsers();
  }

  /// Test WS connection
  Future<void> _test() async {
    var wsAuthResponse =
        await Utils.callApi(() => Singleton().wsAuthApi.webSocketAuth(), true);
    if (wsAuthResponse != null) {
      TestUtils.test(Singleton().profile.url, wsAuthResponse.accessToken);
    }
  }

  /// Show delete users dialog
  Future<void> _deleteSelectedUsersDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('deleteUserConfirm'.tr()),
          content: Text('deleteUserConfirmText'.tr()),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            TextButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.primary),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(35)),
                ),
              ),
              child: Text(
                'yesText'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.surface),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteSelectedUsers();
              },
            ),
            TextButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.primary),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(35)),
                ),
              ),
              onPressed: Navigator.of(context).pop,
              child: Text(
                'noText'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.surface),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Get server invites
  Future<void> _getServerInvites() async {
    if (mounted) {
      setState(() {
        _serverInvites = [];
      });
      var invites = await Utils.callApi(
          () => Singleton().inviteApi.getAllInvites(), true);
      if (mounted) {
        setState(() {
          if (invites != null) {
            _serverInvites = invites;
          }
        });
      }
    }
  }

  /// Shows new invite dialog.
  Future<void> _createNewInvite(BuildContext context) async {
    await showDialog(context: context, builder: DialogUtils.inviteDialog)
        .then((_) async {
      await _getServerInvites();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get color of user profile picture
    Color userColor =
        ColorUtils.getColorFromUsername(Singleton().profile.user.username);

    return PopScope(
      child: Scaffold(
        appBar: _currentPageIndex == 0
            ? AppBar(
                // User icon with first letter
                leading: Transform.scale(
                  scale: 0.7,
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
                          fontSize: 27,
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
                  // Settings
                  IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: 'searchButton'.tr(),
                    onPressed: () {
                      Navigator.of(context).push(PageTransition(
                          type: PageTransitionType.rightToLeftJoined,
                          child: SettingsPage(),
                          childCurrent: widget));
                    },
                  ),
                ],
              )
            : null,
        resizeToAvoidBottomInset: false,
        // Floating button
        floatingActionButton: FloatingActionButton(
          onPressed: _currentPageIndex == 0
              ? () {
                  Navigator.of(context).push(PageTransition(
                      type: PageTransitionType.bottomToTopJoined,
                      child: SearchUserPage(),
                      childCurrent: widget));
                }
              : () async {
                  await _createNewInvite(context);
                },
          shape: const CircleBorder(),
          foregroundColor: Theme.of(context).colorScheme.surface,
          backgroundColor: Theme.of(context).colorScheme.primary,
          tooltip: _currentPageIndex == 0
              ? 'addChat'.tr()
              : 'newInvite'.tr(), // Change tooltip according to page index
          child: Icon(_currentPageIndex == 0
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
                      _currentPageIndex = index;
                    });
                  },
                  selectedIndex: _currentPageIndex,
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
                        'serverInvitesPage'.tr(),
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
                      Visibility(
                        visible: _serverUsers.isNotEmpty,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.all(5),
                            child: ElevatedButton(
                              onPressed: _selectedUsers.isEmpty
                                  ? null
                                  : _deleteSelectedUsersButton,
                              child: Text('deleteUser'.tr()),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _getServerUsers,
                          child: ListView.builder(
                            itemCount: _serverUsers.length,
                            itemBuilder: (context, index) {
                              return SelectUserListItem(_serverUsers[index],
                                  (isSelected) {
                                // Add/remove selected users from list
                                setState(() {
                                  if (isSelected) {
                                    isSelected = isSelected;
                                    _selectedUsers.add(_serverUsers[index].id);
                                  } else {
                                    _selectedUsers
                                        .remove(_serverUsers[index].id);
                                  }
                                });
                              });
                            },
                          ),
                        ),
                      )
                    ],
                  ),
                  // Invites
                  RefreshIndicator(
                    onRefresh: _getServerInvites,
                    child: ListView.builder(
                      itemCount: _serverInvites.length,
                      itemBuilder: (context, index) {
                        return InviteListItem(_serverInvites[index]);
                      },
                    ),
                  )
                ],
              ),
            ),
          )
        ][_currentPageIndex], // Pick widget by current index
      ),
    );
  }
}
