import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MMMMd', () {
    // January 25
    debugPrint(DateFormat.MMMMd().format(DateTime.now().toLocal()));
  });

  test('yMMMMd', () {
    // January 25, 2025
    debugPrint(DateFormat.yMMMMd().format(DateTime.now().toLocal()));
  });

  test('EEEE', () {
    // Friday
    debugPrint(DateFormat.EEEE().format(DateTime.now().toLocal()));
  });
}