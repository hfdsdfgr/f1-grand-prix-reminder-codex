import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grand_prix_reminder/app.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
import 'package:grand_prix_reminder/features/races/race_detail_page.dart';

import 'app_test.dart' show fixture;

Map<String, dynamic> completedRace() => {
  ...fixture(),
  'status': 'completed',
  'lifecycle_phase': 'post_race',
};

Map<String, dynamic> resultFeed({bool empty = false}) => {
  'entries': empty
      ? []
      : [
          {
            'driver': 'Test Driver',
            'team': 'Example Team',
            'classification': '1',
            'grid': 0,
            'points': 25,
            'time': '1:32:00',
            'status': 'Finished',
            'q1': '1:22.000',
            'q2': null,
            'q3': null,
          },
        ],
  'fastest_lap': empty
      ? null
      : {'driver': 'Test Driver', 'lap': 12, 'time': '1:20.123'},
  'source': 'https://example.com/results',
  'updated_at': '2030-09-13T00:00:00Z',
  'stale': false,
};

void main() {
  testWidgets('post-race detail reveals a hidden session on demand', (
    tester,
  ) async {
    final repo = RaceRepository(
      client: MockClient(
        (_) async => http.Response(jsonEncode(resultFeed()), 200),
      ),
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailPage(
          race: Race(completedRace()),
          repository: repo,
          spoilerHidden: true,
          onReveal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Results hidden'), findsOneWidget);
    await tester.tap(find.text('Reveal this session'));
    await tester.pump();
    expect(find.text('Race result'), findsOneWidget);
  });

  testWidgets('pre-race detail prioritizes schedule and hides results', (
    tester,
  ) async {
    final session = Map<String, dynamic>.from(
      (fixture()['sessions'] as List).first as Map,
    );
    final race = Race({
      ...fixture(),
      'lifecycle_phase': 'pre_race',
      'circuit_layout': {
        'id': 'suzuka-2',
        'asset_path': 'assets/circuits/suzuka-2.svg',
        'valid_from': 2022,
        'turns': 18,
        'source': 'https://github.com/f1db/f1db',
        'license': 'CC BY 4.0',
      },
      'next_session': session,
      'sessions': [
        {...session, 'status': 'scheduled'},
      ],
    });
    final repo = RaceRepository(
      client: MockClient((_) async => http.Response('', 503)),
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailPage(race: race, repository: repo),
      ),
    );
    await tester.pump();
    expect(find.text('Pre-race'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Example Circuit circuit layout'),
      findsOneWidget,
    );
    expect(find.text('Weekend schedule'), findsOneWidget);
    expect(find.text('Race result'), findsNothing);
  });

  testWidgets(
    'opens race, changes session, preserves list on back at large text',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final requests = <String>[];
      final repo = RaceRepository(
        client: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path.endsWith('/seasons')) {
            return http.Response(
              jsonEncode([2030, 2029, DateTime.now().year]),
              200,
            );
          }
          final isResult =
              request.url.path.endsWith('/results') ||
              request.url.path.endsWith('/qualifying');
          return http.Response(
            jsonEncode(
              isResult
                  ? resultFeed()
                  : {
                      if (request.url.path.endsWith('next-race'))
                        'race': completedRace()
                      else
                        'races': [completedRace()],
                      'updated_at': '2030-09-13T00:00:00Z',
                      'stale': false,
                    },
            ),
            200,
          );
        }),
      );
      addTearDown(repo.dispose);
      await tester.pumpWidget(GrandPrixApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('赛事').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看详情'));
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      expect(find.text('赛事详情'), findsOneWidget);
      expect(find.text('1:20.123'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('排位赛'));
      await tester.tap(find.text('排位赛'));
      await tester.pumpAndSettle();
      expect(find.text('Q1  1:22.000'), findsOneWidget);
      expect(find.text('Q3  —'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(ChoiceChip, '正赛成绩'));
      await tester.pumpAndSettle();
      expect(requests.where((p) => p.endsWith('/results')).length, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsOneWidget);
      expect(requests.where((p) => p == '/api/v1/races').length, 1);
    },
  );

  testWidgets('result outage retries to explicit empty state', (tester) async {
    var attempts = 0;
    final repo = RaceRepository(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/seasons')) {
          return http.Response(
            jsonEncode([2030, 2029, DateTime.now().year]),
            200,
          );
        }
        if (request.url.path.endsWith('/results')) {
          if (attempts++ == 0) return http.Response('', 503);
          return http.Response(jsonEncode(resultFeed(empty: true)), 200);
        }
        return http.Response(
          jsonEncode({
            'race': completedRace(),
            'races': [completedRace()],
            'updated_at': '2030-09-13T00:00:00Z',
            'stale': false,
          }),
          200,
        );
      }),
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(GrandPrixApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('赛事').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('无法加载成绩，请重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('该场次成绩尚未公布，或暂无历史记录。'), findsOneWidget);
  });
}
