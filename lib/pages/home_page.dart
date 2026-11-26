import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
// Firebase is retired; dependency is commented out in pubspec.yaml.
// import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../utils/nav_transitions.dart';
import 'package:sprintf/sprintf.dart';
import '../pages/chat_page.dart';
import '../utils/websocket_manager.dart';
import '../widgets/chat_list_item.dart';
import '../models/private_message.dart';
import '../utils/cache_utils.dart';
import '../utils/message_notifier.dart';
import '../utils/notification_service.dart';
import 'search_user_page.dart';
import 'settings_page.dart';
import '../utils/dialog_utils.dart';
import '../widgets/invite_list_item.dart';
import 'package:shept_openapi_client_dart/api.dart';
import '../models/user.dart';
import '../utils/admin_format.dart';
import '../utils/singleton.dart';
import '../utils/screen_guard.dart';
import '../utils/share_intent.dart';
import '../utils/utils.dart';
import '../widgets/admin_user_list_item.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// Which rows the chat list shows.
///
/// The roadmap lists folders for unread and favourites; favourites arrive in F7
/// with contacts, so the pinned chats stand in for them.
enum _ChatFilter { all, unread, pinned }

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final WebSocketManager _webSocketManager = WebSocketManager();
  List<User> _serverUsers = [];
  int _currentPageIndex = 0;
  List<ModelsInvite> _serverInvites = [];
  List<MapEntry<User, PrivateMessage>> _chatEntries = [];

  /// Unread incoming messages per conversation id, for the list badges.
  Map<String, int> _unreadCounts = {};

  /// Conversation ids pinned to the top of the list.
  Set<String> _pinnedChats = {};

  /// Read cursors of the chats that publish receipts, for the seen ticks.
  Map<String, DateTime> _peerReadAts = {};

  /// The folder strip floats over the list, so its height is measured instead
  /// of taking layout space; the list pads itself by the same amount.
  final GlobalKey _filterKey = GlobalKey();
  double _filterHeight = 0;

  /// Which rows the list shows; folders without extra storage.
  _ChatFilter _filter = _ChatFilter.all;
  bool _firstLoad = true;
  String? _pendingFid; // Store pending FID

  // Kept in state so switching the bottom navigation back to the admin panel
  // does not drop the selected sub-tab.
  late final TabController _adminTabController =
      TabController(length: 2, vsync: this);
  bool _usersLoading = true;
  bool _usersError = false;
  bool _invitesLoading = true;
  bool _invitesError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load all server users and invites if admin
    if (Singleton().profile.user.admin) {
      _getServerUsers();
      _getServerInvites();
    }
    // Get all conversations with their last messages
    _getConversations();
    // Refresh the list when a message arrives or its state changes; the build
    // method must not create a new future on every rebuild.
    MessageNotifier().addListener(_onMessagesChanged);
    // A screenshot outside the view-once viewer is reported, not blocked: the
    // app cannot prevent it, and pretending otherwise would be a lie.
    ScreenGuard.onScreenshot = _onScreenshot;
    ScreenGuard.start();
    // A pending FCM id is retried when the socket comes up instead of polling.
    Utils.onConnected = _sendPendingFid;
    // Open the chat a notification tap pointed at (after unlocking)
    _openPendingChat();
    // Pictures, videos and links shared from other apps. Started here rather
    // than at launch, so a share can never open over the password screen.
    SharedInbox.start();
    // Taps arriving while Home is alive open the chat right away
    NotificationService.onChatSelected = _openChat;
    // Start checking WebSocket connection
    _webSocketManager.startConnectionCheck();

    // Firebase is retired: FCM registration is commented out, the app still
    // compiles and runs without push.
    // // Request FCM notification permissions
    // FirebaseMessaging.instance.requestPermission(provisional: true);
    //
    // // FID registration - store FID and send when online
    // FirebaseMessaging.instance.onRegistered.listen((fid) async {
    //   _pendingFid = fid;
    //   await _sendPushTargetWhenOnline(fid);
    // }).onError((err) {
    //   if (kDebugMode) {
    //     debugPrint('Error getting FID: $err');
    //   }
    // });
    //
    // // Enable FCM notifications
    // FirebaseMessaging.instance.setAutoInitEnabled(true);
    //
    // // A foreground push is not shown by the OS; show it ourselves.
    // _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
    //   final notification = message.notification;
    //   if (notification == null) {
    //     return;
    //   }
    //   NotificationService().showSecurityNotification(
    //     notification.title ?? 'newLoginTitle'.tr(),
    //     notification.body ?? '',
    //   );
    // });
    //
    // // Register with FCM, the FID arrives via onRegistered
    // _registerForPush();
  }

  /// Foreground pushes: the server warns the other devices about a new login,
  /// and a foreground app has to show that itself.
  /// Firebase is retired; kept commented so the type reference does not pull
  /// the dependency back in.
  // StreamSubscription<RemoteMessage>? _fcmSubscription;

  /// A screenshot of an ordinary message cannot be stopped, only noticed.
  void _onScreenshot() {
    Fluttertoast.showToast(
        msg: 'screenshotDetected'.tr(), backgroundColor: Colors.orange);
  }

  /// Presence is announced when the app comes back and withdrawn when it goes
  /// away: the server keeps nothing, so a stale "online" would never clear.  @override
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Utils.announcePresence();
      // A message whose deadline passed while the app was in the background is
      // gone before it paints again.
      CacheUtils.purgeExpiredMessages().then((_) => MessageNotifier().notify());
    } else if (state == AppLifecycleState.paused) {
      Utils.withdrawPresence();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScreenGuard.onScreenshot = null;
    // _fcmSubscription?.cancel();
    _adminTabController.dispose();
    MessageNotifier().removeListener(_onMessagesChanged);
    if (NotificationService.onChatSelected == _openChat) {
      NotificationService.onChatSelected = null;
    }
    if (Utils.onConnected == _sendPendingFid) {
      Utils.onConnected = null;
    }
    super.dispose();
    // Stop checking WebSocket connection
    _webSocketManager.stopConnectionCheck();
  }

  /// Reload the conversation list after a message or its send/media state
  /// changed.
  void _onMessagesChanged() {
    _getConversations();
  }

  /// Push a pending Firebase installation id once the socket is up.
  Future<void> _sendPendingFid() async {
    final fid = _pendingFid;
    if (fid == null) {
      return;
    }
    await _sendPushTargetWhenOnline(fid);
  }

  /// Register with FCM, the FID arrives via onRegistered
  /// Firebase is retired; kept commented so the dependency stays out.
  // Future<void> _registerForPush() async {
  //   try {
  //     await FirebaseMessaging.instance.register();
  //   } catch (e) {
  //     if (kDebugMode) {
  //       debugPrint('Error registering with FCM: $e');
  //     }
  //   }
  // }

  /// Send FID when online, store when offline
  Future<void> _sendPushTargetWhenOnline(String fid) async {
    // Skip if in offline mode
    if (Singleton().offlineMode) {
      if (kDebugMode) {
        debugPrint('Offline mode - FID will be sent when online');
      }
      return;
    }

    try {
      await Utils.callApi<void>(
        () => Singleton().firebaseApi.setFirebaseToken(
            setFirebaseTokenInput: SetFirebaseTokenInput(token: fid)),
        useSecurity: true,
      ).timeout(Duration(seconds: 10));
      // Sent; the retry loop only covers values that never made it
      if (_pendingFid == fid) {
        _pendingFid = null;
      }
    } catch (e) {
      // Error occurred, keep FID pending
      _pendingFid = fid;
      if (kDebugMode) {
        debugPrint('Error sending FID: $e');
      }
    }
  }

  /// Get all conversations with their last messages
  Future<void> _getConversations() async {
    final chats = await CacheUtils.getLatestPrivateMessages();
    final unread = await CacheUtils.getUnreadCounts();
    final pinned = await CacheUtils.getPinnedConversations();
    final peerReadAts = await CacheUtils.peerReadAts();
    if (!mounted) {
      return;
    }
    setState(() {
      _chatEntries = chats.entries.toList();
      _unreadCounts = unread;
      _pinnedChats = pinned;
      _peerReadAts = peerReadAts;
      _firstLoad = false;
    });
  }

  /// Pin or unpin a conversation. Local only: nothing is sent to the server.
  Future<void> _togglePin(User user) async {
    final pinned = _pinnedChats.contains(user.id);
    await CacheUtils.setConversationPinned(user.id, !pinned);
    if (!mounted) {
      return;
    }
    Fluttertoast.showToast(
        msg: pinned ? 'chatUnpinned'.tr() : 'chatPinned'.tr());
    await _getConversations();
  }

  /// Delete a conversation after the confirmation dialog confirmed it.
  void _deleteChat(User user) {
    DialogUtils.yesNoDialog(
        context, 'deleteChatConfirm'.tr(), 'deleteChatConfirmText'.tr(),
        () async {
      final deleted = await MessageNotifier().deleteChat(user.id);
      if (!deleted) {
        Fluttertoast.showToast(
            msg: 'deleteChatFailed'.tr(), backgroundColor: Colors.red);
      }
      await _getConversations();
    });
  }

  /// Icon shown under a swiped chat row.
  Widget _swipeBackground(Alignment alignment, IconData icon, Color color) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(icon, color: color),
    );
  }

  /// Get server users
  Future<void> _getServerUsers() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _usersError = false;
      _usersLoading = true;
    });
    final users = await Utils.callApi(() => Singleton().userApi.getAllUsers());
    if (!mounted) {
      return;
    }
    setState(() {
      // A failed refresh keeps the rows that are already on screen.
      _usersError = users == null;
      if (users != null) {
        _serverUsers = sortedByUsername(users.map(User.fromModel).toList());
      }
      _usersLoading = false;
    });
  }

  /// Delete one user after the confirmation dialog confirmed it.
  Future<void> _deleteUser(User user) async {
    try {
      await Utils.callApi(
        () => Singleton()
            .userApi
            .deleteUsers(deleteUsersInput: DeleteUsersInput(ids: [user.id])),
        rethrowErr: true,
      );
    } catch (_) {
      // Utils.callApi already surfaced the error as a red toast.
      return;
    }
    if (!mounted) {
      return;
    }
    Fluttertoast.showToast(
        msg: 'userDeleted'.tr(), backgroundColor: Colors.grey);
    await _getServerUsers();
  }

  /// Get server invites
  Future<void> _getServerInvites() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _invitesError = false;
      _invitesLoading = true;
    });
    final invites =
        await Utils.callApi(() => Singleton().inviteApi.getAllInvites());
    if (!mounted) {
      return;
    }
    setState(() {
      _invitesError = invites == null;
      if (invites != null) {
        _serverInvites = invites;
      }
      _invitesLoading = false;
    });
  }

  /// Open the chat of [userId] on top of Home.
  Future<void> _openChat(String userId) async {
    final user = await CacheUtils.getUserById(userId);
    if (user == null || !mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).push(slideUpRoute(ChatPage(user)));
    });
  }

  /// Open the chat a notification tap pointed at. This also covers a locked
  /// app: the tap is remembered and the chat opens after the password page
  /// replaced itself with HomePage.
  Future<void> _openPendingChat() async {
    final userId = Singleton().pendingChatUserId;
    if (userId == null) {
      return;
    }
    Singleton().pendingChatUserId = null;
    await _openChat(userId);
  }

  /// Shows new invite dialog. It has no cancel path, so closing it always
  /// means an invite was created.
  Future<void> _createNewInvite(BuildContext context) async {
    await showDialog(context: context, builder: DialogUtils.inviteDialog);
    await _getServerInvites();
  }

  /// Chats that pass the current folder filter.
  List<MapEntry<User, PrivateMessage>> get _visibleChats {
    switch (_filter) {
      case _ChatFilter.unread:
        return _chatEntries
            .where((chat) => (_unreadCounts[chat.key.id] ?? 0) > 0)
            .toList();
      case _ChatFilter.pinned:
        return _chatEntries
            .where((chat) => _pinnedChats.contains(chat.key.id))
            .toList();
      case _ChatFilter.all:
        return _chatEntries;
    }
  }

  String _filterLabel(_ChatFilter filter) {
    switch (filter) {
      case _ChatFilter.all:
        return 'allChats'.tr();
      case _ChatFilter.unread:
        return 'unreadChats'.tr();
      case _ChatFilter.pinned:
        return 'pinnedChats'.tr();
    }
  }

  /// Folder chips above the list: everything, unread, pinned.
  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final filter in _ChatFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_filterLabel(filter)),
                selected: _filter == filter,
                onSelected: (_) => setState(() {
                  _filter = filter;
                }),
              ),
            ),
        ],
      ),
    );
  }

  /// Get ListView with content
  ListView _getContent(List<MapEntry<User, PrivateMessage>> chats) {
    _firstLoad = false;
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      // The list runs behind the translucent app bar and under the floating
      // folder strip, so it pads itself instead of using the automatic
      // MediaQuery padding.
      padding: EdgeInsets.only(
        top: MediaQuery.viewPaddingOf(context).top +
            kToolbarHeight +
            _filterHeight,
      ),
      itemCount: chats.length,
      itemBuilder: (context, index) {
        // Indexed access: `Map.entries.elementAt` is O(n) and made the list
        // build O(n^2).
        final chat = chats[index];
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: EdgeInsets.only(right: 5, left: 5, bottom: 3),
          // Swipe right pins, swipe left deletes. Both spring back: the gesture
          // opens an action, it never removes a row on its own.
          child: Dismissible(
            key: ValueKey('chat|${chat.key.id}'),
            direction: DismissDirection.horizontal,
            background: _swipeBackground(
                Alignment.centerLeft, Icons.push_pin, scheme.primary),
            secondaryBackground: _swipeBackground(
                Alignment.centerRight, Icons.delete, scheme.error),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                await _togglePin(chat.key);
              } else {
                _deleteChat(chat.key);
              }
              return false;
            },
            child: ChatListItem(
              chat.key,
              chat.value,
              () {
                // Push to chat
                Navigator.of(context).push(slideUpRoute(ChatPage(chat.key)));
              },
              unreadCount: _unreadCounts[chat.key.id] ?? 0,
              pinned: _pinnedChats.contains(chat.key.id),
              peerReadAt: _peerReadAts[chat.key.id],
            ),
          ),
        );
      },
    );
  }

  /// Measures the folder strip: it floats over the list, so the list needs its
  /// height as padding rather than as layout space.
  void _measureFilters() {
    final render = _filterKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) {
      return;
    }
    final height = render.size.height;
    if ((height - _filterHeight).abs() > 0.5) {
      setState(() => _filterHeight = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentPageIndex == 0) {
        _measureFilters();
      }
    });
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
                        .withValues(alpha: 0.5),
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
                          Navigator.of(context).push(stepRoute(SettingsPage()));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      resizeToAvoidBottomInset: false,
      // Floating button, only on the messages tab; the invites tab has its own
      floatingActionButton: _currentPageIndex == 0
          ? FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(stepRoute(SearchUserPage()));
              },
              shape: const CircleBorder(),
              foregroundColor: Theme.of(context).colorScheme.surface,
              backgroundColor: Theme.of(context).colorScheme.primary,
              tooltip: 'addChat'.tr(),
              child: const Icon(Icons.add_comment),
            )
          : null,
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
        Stack(
          children: [
            // Messages and avatar list, behind the chips: rows scroll under
            // them instead of being cut off by a strip of background.
            Positioned.fill(
              child: _firstLoad
                  ? Center(
                      child: Transform.scale(
                        scale: 1.5,
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _visibleChats.isEmpty
                      ? Center(child: Text('noChatsInFilter'.tr()))
                      : _getContent(_visibleChats),
            ),
            // The body sits behind the translucent app bar; the chips do not
            // scroll, so they start below it.
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + kToolbarHeight,
              left: 0,
              right: 0,
              child: Container(key: _filterKey, child: _filterChips()),
            ),
          ],
        ),
        // Admin panel
        Scaffold(
          appBar: AppBar(
            title: Text('adminPage'.tr()),
            bottom: TabBar(
              controller: _adminTabController,
              tabs: <Widget>[
                Tab(child: Text('serverUsersPage'.tr())),
                Tab(child: Text('serverInvitesPage'.tr())),
              ],
            ),
          ),
          body: TabBarView(
            controller: _adminTabController,
            children: <Widget>[
              _usersTab(),
              _invitesTab(),
            ],
          ),
        )
      ][_currentPageIndex], // Pick widget by current index
    );
  }

  /// Rounded surface the admin rows sit in.
  Widget _adminCard(List<Widget> children) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: colors.surfaceContainerHigh,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colors.outlineVariant,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  /// Centred icon + message used for the empty admin lists.
  Widget _adminEmpty(IconData icon, String message) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: colors.secondary),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: colors.secondary)),
        ],
      ),
    );
  }

  /// Centred error message with a retry button, replacing the blank tab of the old UI.
  Widget _adminError(VoidCallback retry) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: colors.error),
          const SizedBox(height: 12),
          Text(
            'loadError'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: retry, child: Text('retry'.tr())),
        ],
      ),
    );
  }

  Widget _adminSpinner() {
    return Center(
      child: Transform.scale(
        scale: 1.5,
        child: const CircularProgressIndicator(),
      ),
    );
  }

  Widget _usersTab() {
    if (_usersLoading && _serverUsers.isEmpty) {
      return _adminSpinner();
    }
    if (_usersError && _serverUsers.isEmpty) {
      return _adminError(_getServerUsers);
    }
    return RefreshIndicator(
      onRefresh: _getServerUsers,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
        children: [
          if (_serverUsers.isEmpty)
            _adminEmpty(Icons.people_outline, 'noUsers'.tr())
          else
            _adminCard([
              for (final user in _serverUsers)
                AdminUserListItem(
                  user,
                  onDelete: () async {
                    await DialogUtils.yesNoDialog(
                      context,
                      'deleteUserConfirm'.tr(),
                      sprintf(
                          'deleteUserConfirmTextName'.tr(), [user.username]),
                      () => _deleteUser(user),
                    );
                  },
                ),
            ]),
        ],
      ),
    );
  }

  Widget _invitesTab() {
    if (_invitesLoading && _serverInvites.isEmpty) {
      return _adminSpinner();
    }
    if (_invitesError && _serverInvites.isEmpty) {
      return _adminError(_getServerInvites);
    }
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _getServerInvites,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 96),
            children: [
              if (_serverInvites.isEmpty)
                _adminEmpty(Icons.mail_outline, 'noInvites'.tr())
              else
                _adminCard([
                  for (final invite in _serverInvites) InviteListItem(invite),
                ]),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () => _createNewInvite(context),
            shape: const CircleBorder(),
            foregroundColor: Theme.of(context).colorScheme.surface,
            backgroundColor: Theme.of(context).colorScheme.primary,
            tooltip: 'newInvite'.tr(),
            child: const Icon(Icons.person_add),
          ),
        ),
      ],
    );
  }
}
