import 'package:easy_localization/easy_localization.dart';

/// Date label of a conversation row and of a search result: today and
/// yesterday by name, then the weekday for the last week, then the date.
///
/// [todayLabel] and [yesterdayLabel] are passed in because a pure helper
/// cannot reach the localization; [now] is injectable for tests. Patterns and
/// month names follow `Intl.defaultLocale`, which the app keeps in sync with
/// the selected language.
String chatDateLabel(
  DateTime when, {
  required String todayLabel,
  required String yesterdayLabel,
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  final date = when.toLocal();
  final time = DateFormat.Hm().format(date);
  final days = DateTime(date.year, date.month, date.day)
      .difference(DateTime(current.year, current.month, current.day))
      .inDays;

  if (days == 0) {
    return '$todayLabel $time';
  }
  if (days == -1) {
    return '$yesterdayLabel $time';
  }
  if (days >= -7) {
    return '${DateFormat.EEEE().format(date)} $time';
  }
  if (date.year == current.year) {
    return DateFormat.MMMMd().format(date);
  }
  return DateFormat.yMMMMd().format(date);
}
