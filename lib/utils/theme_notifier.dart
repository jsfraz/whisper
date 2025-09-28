import 'package:flutter/material.dart';
import '../models/app_theme.dart';

// https://stackoverflow.com/a/65517149/19371130
class ThemeNotifier extends ChangeNotifier {

  ThemeNotifier(this.appTheme);

  AppTheme appTheme;

  void changeTheme(AppTheme theme) {
    appTheme = theme;
    return notifyListeners();
  }
}