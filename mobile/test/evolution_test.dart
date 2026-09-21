import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
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
                'component': 'Floor',
                'title': 'Revised floor',
                'status': 'tested',
                'confidence': 'high',
                'race_id': '2026-1',
                'race': 'Test Grand Prix',
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
    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
