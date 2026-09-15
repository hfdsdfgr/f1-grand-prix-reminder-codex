import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/core/theme.dart';
import 'package:grand_prix_reminder/data/follow_service.dart';
import 'package:grand_prix_reminder/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('follow service persists stable IDs without duplicates', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final follows = FollowService(preferences);
    await follows.toggleDriver('drv_norris', 'Lando Norris');
    await follows.toggleTeam('tem_mclaren', 'McLaren');
    expect(follows.followsDriver('drv_norris'), isTrue);
    expect(follows.followsTeam('tem_mclaren'), isTrue);
    final restored = FollowService(preferences);
    expect(restored.drivers.single.name, 'Lando Norris');
    expect(restored.teams.single.id, 'tem_mclaren');
    await restored.toggleDriver('drv_norris', 'Lando Norris');
    expect(restored.drivers, isEmpty);
  });

  testWidgets('settings manages follows at large text in dark landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final follows = FollowService(await SharedPreferences.getInstance());
    await follows.toggleDriver('drv_norris', 'Lando Norris');
    await tester.pumpWidget(
      MaterialApp(
        theme: raceTheme(Brightness.light),
        darkTheme: raceTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: SettingsPage(
          spoilerFree: false,
          onSpoilerFreeChanged: (_) {},
          follows: follows,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lando Norris'), 160);
    expect(find.text('Lando Norris'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Unfollow'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unfollow'));
    await tester.pumpAndSettle();
    expect(follows.drivers, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
