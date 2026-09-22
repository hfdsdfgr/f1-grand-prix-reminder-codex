import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/data/follow_service.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
import 'package:grand_prix_reminder/shared/race_briefing_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _briefing({
  List<Map<String, dynamic>> insights = const [],
}) => {
  'race_id': '2026-14',
  'insights': insights,
  'sources': [
    {'provider': 'McLaren', 'url': 'https://www.mclaren.com/racing/formula-1/'},
  ],
  'updated_at': '2026-06-14T12:00:00Z',
  'stale': false,
};

void main() {
  test('race evolution uses its published per-race endpoint', () async {
    late Uri requested;
    final repository = RaceRepository(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({'race_id': '2026-14', 'upgrades': []}),
          200,
        );
      }),
    );
    addTearDown(repository.dispose);

    final feed = await repository.evolutionRace('2026-14');

    expect(requested.path, '/api/v1/evolution/2026-14');
    expect(feed.upgrades, isEmpty);
  });

  testWidgets('briefing handles an API-backed empty state', (tester) async {
    final repository = RaceRepository(
      client: MockClient(
        (_) async => http.Response(jsonEncode(_briefing()), 200),
      ),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RaceBriefingView(repository: repository, raceId: '2026-14'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No verified briefing is available for this race.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'spoiler-free briefing hides source-backed conclusions until reveal',
    (tester) async {
      final repository = RaceRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(
              _briefing(
                insights: [
                  {
                    'topic': 'Race assessment',
                    'detail': 'A result conclusion.',
                    'sources': [
                      {
                        'provider': 'McLaren',
                        'url': 'https://www.mclaren.com/racing/formula-1/',
                      },
                    ],
                  },
                ],
              ),
            ),
            200,
          ),
        ),
      );
      addTearDown(repository.dispose);
      var revealed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: RaceBriefingView(
            repository: repository,
            raceId: '2026-14',
            spoilerHidden: true,
            onReveal: () => revealed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Briefing hidden'), findsOneWidget);
      expect(find.text('A result conclusion.'), findsNothing);
      await tester.tap(find.text('Reveal this session'));
      expect(revealed, isTrue);
    },
  );

  testWidgets('followed source-backed briefing content is ordered first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final follows = FollowService(await SharedPreferences.getInstance());
    await follows.toggleDriver('drv_norris', 'Lando Norris');
    final repository = RaceRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(
            _briefing(
              insights: [
                {'topic': 'Other', 'detail': 'Other content.', 'sources': []},
                {
                  'topic': 'Driver concerns',
                  'detail': 'Lando Norris feedback.',
                  'sources': [],
                },
              ],
            ),
          ),
          200,
        ),
      ),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RaceBriefingView(
          repository: repository,
          raceId: '2026-14',
          follows: follows,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Driver concerns')).dy,
      lessThan(tester.getTopLeft(find.text('Other')).dy),
    );
  });
}
