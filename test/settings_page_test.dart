import 'package:brepsight/src/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings exposes persistent appearance choices', (tester) async {
    ThemeMode selected = ThemeMode.system;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          themeMode: selected,
          onThemeModeChanged: (value) => selected = value,
          motionViewEnabled: false,
          motionSensitivity: 1,
          onMotionViewChanged: (_) {},
          onMotionSensitivityChanged: (_) {},
          onMotionRecenter: () {},
        ),
      ),
    );

    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('亮色'), findsOneWidget);
    expect(find.text('暗色'), findsOneWidget);

    await tester.tap(find.text('暗色'));
    await tester.pump();
    expect(selected, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gyro controls expose enable sensitivity and recenter',
      (tester) async {
    bool enabled = true;
    double sensitivity = 1.0;
    var recentered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          motionViewEnabled: enabled,
          motionSensitivity: sensitivity,
          onMotionViewChanged: (value) => enabled = value,
          onMotionSensitivityChanged: (value) => sensitivity = value,
          onMotionRecenter: () => recentered = true,
        ),
      ),
    );

    expect(find.text('陀螺仪辅助视角'), findsOneWidget);
    expect(find.text('运动灵敏度'), findsOneWidget);
    expect(find.text('重新居中运动视角'), findsOneWidget);

    await tester.tap(find.text('重新居中运动视角'));
    await tester.pump();
    expect(recentered, isTrue);
    expect(tester.takeException(), isNull);
  });
}
