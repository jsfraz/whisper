import 'package:flutter/material.dart';
import '../utils/singleton.dart';

class PageNavigatorObserver extends NavigatorObserver {
  @override
  void didChangeTop(Route topRoute, Route? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);
    Singleton().currentRoute = topRoute;
  }
}
