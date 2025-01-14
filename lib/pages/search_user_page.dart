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
    setState(() {
      _loading = true;
      _users = [];
    });

    // Empty search
    if (_controllerSearch.text.isEmpty) {
      setState(() {
        _loading = false;
      });
      return;
    }

    // Get users from server
    var users = await Utils.callApi(
        () => Singleton().userApi.searchUsers(_controllerSearch.text), true);
    setState(() {
      if (users != null) {
        for (var x in users) {
          _users.add(User.fromModel(x));
        }
      }
    });

    setState(() {
      _loading = false;
    });
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
                  fillColor: Theme.of(context).colorScheme.surfaceBright,
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
                    return UserListItem(_users[index], () async {
                      // TODO return to home page when pop
                      // Open chat page
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => ChatPage(_users[index])));
                    });
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
