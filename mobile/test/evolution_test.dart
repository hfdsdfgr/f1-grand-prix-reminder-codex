import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
import 'package:grand_prix_reminder/features/evolution/car_viewer.dart';
import 'package:grand_prix_reminder/features/evolution/evolution_page.dart';

void main() {
  testWidgets('upgrade archive expands attributed details at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = RaceRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'upgrades': [
              {
                'id': 'u',
                'team_id': 't',
                'team': 'Test Team',
                'component_id': 'floor',
                'component': 'Floor',
                'title': 'Revised floor',
                'status': 'tested',
                'confidence': '0.62',
                'race_id': '2026-1',
                'race': 'Test Grand Prix',
                'round': 1,
                'change': 'New edge',
                'goal': null,
                'expected_effect': null,
                'sources': [
                  {
                    'provider': 'Test source',
                    'url': 'https://example.com/test',
                  },
                ],
              },
              {
                'id': 'spanish-floor',
                'team_id': 'cadillac',
                'team': 'Cadillac',
                'component_id': 'floor',
                'component': 'Floor',
                'title': 'Floor update',
                'status': 'modified',
                'confidence': 'high',
                'race_id': '2026-3',
                'race': 'Spanish Grand Prix',
                'round': 3,
                'change': 'Revised floor edge',
                'goal': null,
                'expected_effect': null,
                'sources': [
                  {
                    'provider': 'Formula1.com',
                    'url': 'https://www.formula1.com/test',
                  },
                ],
              },
              {
                'id': 'unmapped',
                'team_id': 't',
                'team': 'Test Team',
                'component_id': 'brake_duct',
                'component': 'Brake duct',
                'title': 'Brake duct update',
                'status': 'tested',
                'confidence': 'high',
                'race_id': '2026-2',
                'race': 'Next Grand Prix',
                'round': 2,
                'change': 'New duct',
                'goal': null,
                'expected_effect': null,
                'sources': [
                  {
                    'provider': 'Test source',
                    'url': 'https://example.com/test',
                  },
                ],
              },
            ],
            'timeline': [
              {
                'race_id': '2026-1',
                'race': 'Test Grand Prix',
                'round': 1,
                'upgrade_ids': ['u'],
              },
              {
                'race_id': '2026-2',
                'race': 'Next Grand Prix',
                'round': 2,
                'upgrade_ids': ['unmapped'],
              },
              {
                'race_id': '2026-3',
                'race': 'Spanish Grand Prix',
                'round': 3,
                'upgrade_ids': ['spanish-floor'],
              },
            ],
            'stale': true,
          }),
          200,
        ),
      ),
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: EvolutionPage(repository: repo, enableGltf: false),
              ),
            ),
          ),
        ),
      ),
    );
    // Asset IO runs outside the widget test's fake clock.
    for (
      var i = 0;
      i < 100 && !tester.any(find.byKey(const ValueKey('car-canvas')));
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('car-canvas')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(
      find.text('Showing saved upgrades. They may have changed.'),
      findsOneWidget,
    );
    final event = find.byKey(const ValueKey('evolution-2026-1'));
    await tester.ensureVisible(event);
    await tester.tap(event);
    await tester.pumpAndSettle();
    final car = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('car-canvas')),
    );
    expect((car.painter! as CarPainter).selected, 'floor');
    final unmappedEvent = find.byKey(const ValueKey('evolution-2026-2'));
    await tester.ensureVisible(unmappedEvent);
    await tester.tap(unmappedEvent);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('unmapped')));
    await tester.tap(find.byKey(const ValueKey('unmapped')));
    await tester.pumpAndSettle();
    expect(
      find.text('This upgrade has no compatible 3D component mapping.'),
      findsOneWidget,
    );
    expect((car.painter! as CarPainter).selected, 'floor');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(event);
    await tester.tap(event);
    await tester.pumpAndSettle();
    final compare = find.byKey(const ValueKey('specification-compare'));
    await tester.ensureVisible(compare);
    await tester.tap(compare);
    await tester.pumpAndSettle();
    expect(find.text('Launch specification'), findsOneWidget);
    expect(find.textContaining('New edge'), findsWidgets);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('ghost-compare')))
          .onChanged,
      isNull,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('u')));
    await tester.tap(find.byKey(const ValueKey('u')));
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/test'), findsOneWidget);
    expect(find.text('Low · 0.62'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final teamSelector = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(teamSelector);
    await tester.tap(teamSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadillac F1 Team').last);
    await tester.pumpAndSettle();
    final spanish = find.byKey(const ValueKey('evolution-2026-3'));
    await tester.ensureVisible(spanish);
    await tester.tap(spanish);
    await tester.pumpAndSettle();
    await tester.ensureVisible(compare);
    await tester.tap(compare);
    await tester.pumpAndSettle();
    final ghost = find.byKey(const ValueKey('ghost-compare'));
    expect(tester.widget<SwitchListTile>(ghost).onChanged, isNull);
    expect(
      find.text('Two verified generation geometries are required.'),
      findsOneWidget,
    );
    expect(find.textContaining('modified'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test(
    'all lifecycle values remain stable and unknown values are conservative',
    () {
      for (final status in evolutionLifecycleStatuses) {
        final entry = UpgradeEntry({
          'id': status,
          'team_id': 't',
          'team': 'Team',
          'component_id': 'floor',
          'component': 'Floor',
          'title': 'Update',
          'status': status,
          'confidence': 'high',
          'sources': <dynamic>[],
        });
        expect(entry.status, status);
      }
      final unknown = UpgradeEntry({
        'id': 'x',
        'team_id': 't',
        'team': 'Team',
        'component_id': 'floor',
        'component': 'Floor',
        'title': 'Update',
        'status': 'invented',
        'confidence': 'high',
        'sources': <dynamic>[],
      });
      expect(unknown.status, 'unknown');
    },
  );
}
