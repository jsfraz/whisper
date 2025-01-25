import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import '../widgets/user_list_item.dart';
import 'chat_page.dart';

class SearchUserPage extends StatefulWidget {
  const SearchUserPage({super.key});

  @override
  State<SearchUserPage> createState() => _SearchUserPageState();
}

class _SearchUserPageState extends State<SearchUserPage> {
  final _controllerSearch = TextEditingController();
  List<User> _users = [];
  bool _loading = false;

  /// Search users
  Future<void> _searchUsers() async {
    if (context.mounted) {
      setState(() {
        _loading = true;
        _users = [];
      });
    }

    // Empty search
    if (_controllerSearch.text.isEmpty) {
      if (context.mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    // Get users from server
    var users = await Utils.callApi(
        () => Singleton().userApi.searchUsers(_controllerSearch.text));
    if (context.mounted) {
      setState(() {
        if (users != null) {
          for (var x in users) {
            _users.add(User.fromModel(x));
          }
        }
      });
    }

    if (context.mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controllerSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('searchUserPage'.tr()),
      ),
      resizeToAvoidBottomInset: false,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Seatch field
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: TextField(
                controller: _controllerSearch,
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
                  suffixIcon: IconButton(
                    onPressed: _searchUsers,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
            // Loading
            Visibility(
              visible: _loading,
              child: const Padding(
                padding: EdgeInsets.only(top: 20, left: 7, right: 7),
                child: CircularProgressIndicator(),
              ),
            ),
            // Users list
            Visibility(
              visible: !_loading,
              child: Expanded(
                child: ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: UserListItem(_users[index], () async {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (context) => ChatPage(_users[index])),
                          (route) =>
                              route.isFirst, // Returns true only for Home page
                        );
                      }),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
