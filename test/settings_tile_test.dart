import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shept/widgets/settings_tile.dart';

void main() {
  testWidgets('row height does not depend on a trailing widget',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SettingsTile(icon: Icons.palette, label: 'plain', onPressed: () {}),
            SettingsTile(
              icon: Icons.notifications,
              label: 'switch',
              trailing: Switch(value: true, onChanged: (_) {}),
            ),
          ],
        ),
      ),
    ));

    final plain = tester.getSize(find.byType(SettingsTile).at(0));
    final withSwitch = tester.getSize(find.byType(SettingsTile).at(1));
    expect(plain.height, withSwitch.height);
    expect(plain.width, withSwitch.width);
  });
}
