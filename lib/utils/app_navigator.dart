import 'package:flutter/widgets.dart';

/// Navigator of the running app, for code that has no widget of its own: an
/// inbound share has to open a chat picker before any screen exists.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
