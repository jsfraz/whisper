import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import '../widgets/user_list_item.dart';
import 'chat_page.dart';

typedef UserSearchCallback = Future<List<User>?> Function(String query);

class SearchUserPage extends StatefulWidget {
  const SearchUserPage({this.onUserSelected, this.search, super.key});

  /// When set, a tapped user is passed here instead of opening the chat.
  final void Function(User)? onUserSelected;

  /// Search implementation; defaults to the server API.
  final UserSearchCallback? search;

  @override
  State<SearchUserPage> createState() => _SearchUserPageState();
}

class _SearchUserPageState extends State<SearchUserPage> {
  static const _debounceDuration = Duration(milliseconds: 250);

  final _controllerSearch = TextEditingController();
  List<User> _users = [];
  bool _loading = false;
  bool _error = false;
  bool _searched = false;
  Timer? _debounce;

  /// Invalidates in-flight requests as soon as the query changes.
  int _generation = 0;

  Future<List<User>?> _performSearch(String query) async {
    final search = widget.search;
    if (search != null) {
      return search(query);
    }
    final users =
        await Utils.callApi(() => Singleton().userApi.searchUsers(query));
    return users?.map(User.fromModel).toList();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final generation = ++_generation;

    if (query.isEmpty) {
      setState(() {
        _users = [];
        _loading = false;
        _error = false;
        _searched = false;
      });
      return;
    }

    setState(() {
      _error = false;
    });
    _debounce = Timer(_debounceDuration, () => _search(query, generation));
  }

  Future<void> _search(String query, int generation) async {
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });

    final users = await _performSearch(query);
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _loading = false;
      _searched = true;
      if (users == null) {
        _error = true;
      } else {
        _users = users;
        _error = false;
      }
    });
  }

  void _submitQuery(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      return;
    }
    final generation = ++_generation;
    _search(query, generation);
  }

  void _retry() {
    _submitQuery(_controllerSearch.text);
  }

  void _clearQuery() {
    _controllerSearch.clear();
    _onQueryChanged('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controllerSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('searchUserPage'.tr()),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Search field
              Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: TextField(
                  controller: _controllerSearch,
                  onChanged: _onQueryChanged,
                  onSubmitted: _submitQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'enterUsername'.tr(),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.surfaceBright
                        : Theme.of(context).colorScheme.surfaceDim,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _controllerSearch.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'clearSearch'.tr(),
                                onPressed: _clearQuery,
                                icon: const Icon(Icons.close),
                              )
                            : null,
                  ),
                ),
              ),
              if (_error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text('userSearchFailed'.tr())),
                      TextButton(
                        onPressed: _retry,
                        child: Text('retry'.tr()),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _users.isEmpty
                    ? Center(
                        child: !_loading && !_error && _searched
                            ? Text('noUsersFound'.tr())
                            : const SizedBox.shrink(),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: UserListItem(_users[index], () async {
                              final onUserSelected = widget.onUserSelected;
                              if (onUserSelected != null) {
                                onUserSelected(_users[index]);
                                return;
                              }
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        ChatPage(_users[index])),
                                (route) => route
                                    .isFirst, // Returns true only for Home page
                              );
                            }),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
