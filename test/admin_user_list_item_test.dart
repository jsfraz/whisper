import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shept/models/user.dart';
import 'package:shept/widgets/admin_user_list_item.dart';

Widget app(User user, VoidCallback onDelete) {
  return MaterialApp(
    home: Scaffold(body: AdminUserListItem(user, onDelete: onDelete)),
  );
}

void main() {
  testWidgets('shows the initial, the name and no badge for a normal user',
      (tester) async {
    await tester.pumpWidget(app(User('1', 'test', 'key', false), () {}));

    expect(find.text('T'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
    expect(find.text('adminBadge'), findsNothing);
  });

  testWidgets('marks admins with a badge', (tester) async {
    await tester.pumpWidget(app(User('1', 'root', 'key', true), () {}));

    expect(find.text('adminBadge'), findsOneWidget);
  });

  testWidgets('the overflow menu offers the delete action', (tester) async {
    var deleted = 0;
    await tester.pumpWidget(app(User('1', 'test', 'key', false), () {
      deleted++;
    }));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('deleteUser'), findsOneWidget);
    expect(deleted, 0);

    await tester.tap(find.text('deleteUser'));
    await tester.pumpAndSettle();

    expect(deleted, 1);
  });
}
