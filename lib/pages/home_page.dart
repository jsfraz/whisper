import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';
import 'package:provider/provider.dart';
import '../pages/chat_page.dart';
import '../utils/websocket_manager.dart';
import '../widgets/chat_list_item.dart';
import '../models/private_message.dart';
import '../utils/cache_utils.dart';
import '../utils/message_notifier.dart';
import 'search_user_page.dart';
import 'settings_page.dart';
import '../utils/dialog_utils.dart';
import '../widgets/invite_list_item.dart';
import 'package:whisper_openapi_client_dart/api.dart';
import '../models/user.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import '../widgets/select_user_list_item.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final WebSocketManager _webSocketManager = WebSocketManager();
  List<User> _serverUsers = [];
  List<int> _selectedUsers = [];
  int _currentPageIndex = 0;
  List<ModelsInvite> _serverInvites = [];
  Map<User, PrivateMessage> _chats = {};
  bool _firstLoad = true;
  String? _pendingFcmToken; // Store pending token

  @override
  void initState() {
    super.initState();
    // Load all server users and invites if admin
    if (Singleton().profile.user.admin) {
      _getServerUsers();
      _getServerInvites();
    }
    // Get all conversations with their last messages
    _getConversations();
    // Start checking WebSocket connection
    _webSocketManager.startConnectionCheck();

    // TODO set icon, sound and vibration patter (same as local notifications)
    // Request FCM notification permissions
    FirebaseMessaging.instance.requestPermission(provisional: true);

    // FCM token refresh - store token and send when online
    FirebaseMessaging.instance.onTokenRefresh.listen((fcmToken) async {
      _pendingFcmToken = fcmToken;
      await _sendFcmTokenWhenOnline(fcmToken);
    }).onError((err) {
      if (kDebugMode) {
        debugPrint('Error getting FCM token: $err');
      }
    });
    
    // Enable FCM notifications
    FirebaseMessaging.instance.setAutoInitEnabled(true);
    
    // Set initial FCM token
    _setFcmToken();

    // Listen to offline mode changes to send pending tokens
    _listenToConnectivityChanges();
  }

  @override
  void dispose() {
    super.dispose();
    // Stop checking WebSocket connection
    _webSocketManager.stopConnectionCheck();
  }

  /// Listen to connectivity changes and send pending FCM token
  void _listenToConnectivityChanges() {
    // Check periodically if we came back online and have a pending token
    Timer.periodic(Duration(seconds: 30), (timer) {
      if (!Singleton().offlineMode && _pendingFcmToken != null) {
        _sendFcmTokenWhenOnline(_pendingFcmToken!);
      }
    });
  }

  /// Set FCM token on server with offline mode handling
  Future<void> _setFcmToken() async {
    try {
      var token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        return;
      }
      _pendingFcmToken = token;
      await _sendFcmTokenWhenOnline(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error setting FCM token: $e');
      }
    }
  }

  // FIXME token is being set all the time
  /// Send FCM token when online, store when offline
  Future<void> _sendFcmTokenWhenOnline(String token) async {
    // Skip if in offline mode
    if (Singleton().offlineMode) {
      if (kDebugMode) {
        debugPrint('Offline mode - FCM token will be sent when online');
      }
      return;
    }

    try {
      await Utils.callApi<void>(
        () => Singleton().firebaseApi.setFirebaseToken(
          setFirebaseTokenInput: SetFirebaseTokenInput(token: token)
        ),
        useSecurity: true,
      ).timeout(
        Duration(seconds: 10),
        onTimeout: () => null,
      );
    } catch (e) {
      // Error occurred, keep token pending
      _pendingFcmToken = token;
      if (kDebugMode) {
        debugPrint('Error sending FCM token: $e');
      }
    }
  }

  /// Get all conversations with their last messages
  Future<void> _getConversations() async {
    _chats = await CacheUtils.getLatestPrivateMessages();
    if (context.mounted) {
      setState(() {});
    }
  }

  /// Get server users
  Future<void> _getServerUsers() async {
    if (mounted) {
      setState(() {
        _serverUsers = [];
        _selectedUsers = [];
      });
      var users = await Utils.callApi(() => Singleton().userApi.getAllUsers());
      if (users != null) {
        for (var x in users) {
          _serverUsers.add(User.fromModel(x));
        }
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  /// Delete selected users
  Future<void> _deleteSelectedUsers() async {
    setState(() {
      _serverUsers =
          []; // I am unable to deactivate the user checkbox, so I will make all the users vanish so it will reset itself :)
    });
    // Delete selected users
    await Utils.callApi(() => Singleton()
        .userApi
        .deleteUsers(deleteUsersInput: DeleteUsersInput(ids: _selectedUsers)));
    setState(() {
      _selectedUsers = [];
    });
    // Refresh users
    await _getServerUsers();
  }

  /// Get server invites
  Future<void> _getServerInvites() async {
    if (mounted) {
      setState(() {
        _serverInvites = [];
      });
      var invites =
          await Utils.callApi(() => Singleton().inviteApi.getAllInvites());
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

  /// Get ListView with content
  ListView _getContent(Map<User, PrivateMessage> chats) {
    _firstLoad = false;
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats.entries.elementAt(index);
        return Padding(
          padding: EdgeInsets.only(right: 5, left: 5, bottom: 3),
          child: ChatListItem(chat.key, chat.value, () {
            // Push to chat
            Navigator.of(context).push(PageTransition(
                duration: const Duration(milliseconds: 300),
                reverseDuration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                type: PageTransitionType.bottomToTopJoined,
                child: ChatPage(chat.key),
                childCurrent: widget));
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<MessageNotifier>();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _currentPageIndex == 0
          ? PreferredSize(
              preferredSize: Size(
                double.infinity,
                56.0,
              ),
              child: ClipRRect(
                child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: AppBar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.2),
                      // User icon with first letter
                      leading: Transform.scale(
                        scale: 0.65,
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: Singleton().profile.user.avatarColor,
                          child: Text(
                            Singleton().profile.user.username.isNotEmpty
                                ? Singleton()
                                    .profile
                                    .user
                                    .username[0]
                                    .toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 24,
                              color: Singleton().profile.user.avatarTextColor,
                            ),
                          ),
                        ),
                      ),
                      // Title
                      title: Text('msgPage'.tr()),
                      // Action buttons
                      actions: [
                        // Settings
                        IconButton(
                          icon: const Icon(Icons.settings),
                          tooltip: 'settingsButton'.tr(),
                          onPressed: () {
                            Navigator.of(context).push(PageTransition(
                              duration: const Duration(milliseconds: 300),
                              reverseDuration:
                                  const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              type: PageTransitionType.rightToLeftJoined,
                              child: SettingsPage(),
                              childCurrent: widget,
                            ));
                          },
                        ),
                      ],
                    )),
              ),
            )
          : null,
      resizeToAvoidBottomInset: false,
      // Floating button
      floatingActionButton: FloatingActionButton(
        onPressed: _currentPageIndex == 0
            ? () {
                Navigator.of(context).push(PageTransition(
                    duration: const Duration(milliseconds: 300),
                    reverseDuration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
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
          ? SafeArea(
              child: SizedBox(
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
            ))
          : null,
      // Body
      body: <Widget>[
        // Messages
        Column(
          children: [
            SizedBox(height: 10),
            // Messages and avatar list
            Expanded(
              child: FutureBuilder<Map<User, PrivateMessage>>(
                  future: notifier.getLatestPrivateMessages(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _firstLoad) {
                      return Center(
                        child: Transform.scale(
                          scale: 1.5,
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    // Set data
                    if (snapshot.hasData) {
                      _chats = snapshot.data!;
                    }
                    // Return chats
                    return _getContent(_chats);
                  }),
            ),
          ],
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
                                : () async {
                                    await DialogUtils.yesNoDialog(
                                        context,
                                        'deleteUserConfirm'.tr(),
                                        'deleteUserConfirmText'.tr(),
                                        _deleteSelectedUsers);
                                  },
                            child: Text('deleteUser'.tr()),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _getServerUsers,
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          itemCount: _serverUsers.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SelectUserListItem(_serverUsers[index],
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
                              }),
                            );
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
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
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
    );
  }
}
