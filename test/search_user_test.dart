import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/user.dart';
import 'package:whisper/pages/search_user_page.dart';

User user(String name) => User(name, name, 'public-key', false);

Widget app(SearchUserPage page) => MaterialApp(home: page);

void main() {
  testWidgets('searches after the debounce and clears the results',
      (tester) async {
    final calls = <String>[];
    Future<List<User>?> search(String query) async {
      calls.add(query);
      return [user('result-$query')];
    }

    await tester.pumpWidget(app(SearchUserPage(search: search)));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);

    await tester.enterText(field, 'a');
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, isEmpty);

    await tester.enterText(field, 'ab');
    await tester.pump(const Duration(milliseconds: 249));
    expect(calls, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(calls, ['ab']);
    expect(find.text('result-ab'), findsOneWidget);

    await tester.tap(find.byTooltip('clearSearch'));
    await tester.pumpAndSettle();
    expect(find.text('result-ab'), findsNothing);
    expect(calls, ['ab']);
  });

  testWidgets('ignores a stale response', (tester) async {
    final first = Completer<List<User>?>();
    final second = Completer<List<User>?>();
    final calls = <String>[];
    Future<List<User>?> search(String query) {
      calls.add(query);
      return query == 'a' ? first.future : second.future;
    }

    await tester.pumpWidget(app(SearchUserPage(search: search)));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);

    await tester.enterText(field, 'a');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(field, 'ab');
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, ['a', 'ab']);

    second.complete([user('new')]);
    await tester.pumpAndSettle();
    expect(find.text('new'), findsOneWidget);

    first.complete([user('old')]);
    await tester.pumpAndSettle();
    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsNothing);
  });

  testWidgets('keeps results on error and retries', (tester) async {
    var fail = false;
    Future<List<User>?> search(String query) async =>
        fail ? null : [user('alice')];

    await tester.pumpWidget(app(SearchUserPage(search: search)));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);

    await tester.enterText(field, 'a');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('alice'), findsOneWidget);

    fail = true;
    await tester.enterText(field, 'ab');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('userSearchFailed'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    expect(find.text('userSearchFailed'), findsNothing);
    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets('shows the empty result state', (tester) async {
    await tester.pumpWidget(app(SearchUserPage(search: (_) async => [])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('noUsersFound'), findsOneWidget);
  });
}
