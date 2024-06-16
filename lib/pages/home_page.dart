import 'package:flutter/material.dart';
import 'package:whisper/utils/singleton.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<HomePage> {
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
