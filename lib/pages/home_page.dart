import 'package:flutter/material.dart';
import 'login_page.dart';
import '../utils/singleton.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<HomePage> {
  @override
  void initState() {
    // Check refresh token
    if (Singleton().profile.isRefreshTokenExpired()) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (context) => const LoginPage('')));
    } else {
      // Check access token
      if (Singleton().profile.isAccessTokenExpired()) {
        // TODO Refresh access token
      }
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Center(
              child: Text('Hello ${Singleton().profile.user.username}!')),
        ),
      ),
    );
  }
}
