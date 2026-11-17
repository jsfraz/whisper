import 'package:easy_localization/easy_localization.dart';
// intl is pinned through easy_localization; same import as the app itself.
// ignore: depend_on_referenced_packages
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/chat_date.dart';

void main() {
  final now = DateTime(2026, 6, 10, 12);

  setUpAll(() async {
    await initializeDateFormatting('en');
    Intl.defaultLocale = 'en';
  });

  String label(DateTime when) => chatDateLabel(when,
      todayLabel: 'Today', yesterdayLabel: 'Yesterday', now: now);

  test('today carries the localized label and the time', () {
    expect(label(DateTime(2026, 6, 10, 9, 5)), 'Today 09:05');
  });

  test('yesterday carries its own label', () {
    expect(label(DateTime(2026, 6, 9, 23, 59)), 'Yesterday 23:59');
  });

  test('the last week shows the weekday name', () {
    final when = DateTime(2026, 6, 7, 8, 30);
    expect(label(when), '${DateFormat.EEEE().format(when)} 08:30');
  });

  test('an older message this year shows the date without the year', () {
    final when = DateTime(2026, 5, 3, 8);
    expect(label(when), DateFormat.MMMMd().format(when));
    expect(label(when).contains('2026'), isFalse);
  });

  test('a message from another year shows the year', () {
    final when = DateTime(2025, 12, 31, 8);
    expect(label(when), DateFormat.yMMMMd().format(when));
    expect(label(when).contains('2025'), isTrue);
  });
}
