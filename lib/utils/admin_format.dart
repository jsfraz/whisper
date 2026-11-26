import '../models/user.dart';

/// Remaining lifetime of an invite, bucketed for a list row.
///
/// Returns the largest sensible unit and its value, or `null` once the
/// invite expired. `min` is clamped to at least 1 so a fresh invite never
/// reads "in 0 min".
({int value, String unit})? inviteRemaining(Duration remaining) {
  if (remaining.isNegative) {
    return null;
  }
  if (remaining.inMinutes < 60) {
    return (value: remaining.inMinutes.clamp(1, 59), unit: 'min');
  }
  if (remaining.inHours < 24) {
    return (value: remaining.inHours, unit: 'h');
  }
  return (value: remaining.inDays, unit: 'd');
}

/// Users sorted by name, the way the admin list shows them.
List<User> sortedByUsername(List<User> users) {
  final sorted = [...users];
  sorted.sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
  return sorted;
}
