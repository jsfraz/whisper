import 'package:flutter_test/flutter_test.dart';
import 'package:shept/models/user.dart';
import 'package:shept/utils/admin_format.dart';

User user(String name) => User(name, name, 'public-key', false);

void main() {
  test('invite lifetime is bucketed into minutes, hours and days', () {
    expect(
        inviteRemaining(const Duration(seconds: 20)), (value: 1, unit: 'min'));
    expect(
        inviteRemaining(const Duration(minutes: 14)), (value: 14, unit: 'min'));
    expect(inviteRemaining(const Duration(minutes: 90)), (value: 1, unit: 'h'));
    expect(inviteRemaining(const Duration(days: 3, hours: 5)),
        (value: 3, unit: 'd'));
  });

  test('expired invites have no remaining lifetime', () {
    expect(inviteRemaining(const Duration(seconds: -1)), isNull);
  });

  test('users are sorted by name, case insensitive', () {
    final sorted =
        sortedByUsername([user('zdeněk'), user('Adam'), user('bob')]);
    expect(sorted.map((u) => u.username), ['Adam', 'bob', 'zdeněk']);
  });

  test('sorting keeps the input list untouched', () {
    final users = [user('b'), user('a')];
    sortedByUsername(users);
    expect(users.map((u) => u.username), ['b', 'a']);
  });
}
