import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grand_prix_reminder/app.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
import 'package:grand_prix_reminder/features/home/home_page.dart';

Map<String, dynamic> fixture() => {
  'id': '2030-1',
  'name': 'Test Grand Prix',
  'circuit': 'Example Circuit',
  'date': '2030-09-15',
  'starts_at': '2030-09-15T12:00:00Z',
  'source': 'https://api.jolpi.ca/ergast/f1/2030/1/',
  'sessions': [
    {'kind': 'Race', 'starts_at': '2030-09-15T12:00:00Z'},
  ],
};

void main() {
  final dispatcher =
      TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
  dispatcher.localeTestValue = const Locale('zh', 'CN');
  dispatcher.localesTestValue = const [Locale('zh', 'CN')];
  test('repository restores the last successful schedule offline', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final online = RaceRepository(
      preferences: preferences,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'race': fixture(),
            'stale': false,
            'updated_at': '2030-09-13T00:00:00Z',
          }),
          200,
        ),
      ),
    );
    await online.load();
    online.dispose();
    final offline = RaceRepository(
      preferences: preferences,
      client: MockClient((_) async => http.Response('', 503)),
    );
    final restored = await offline.load();
    expect(restored.stale, isTrue);
    expect(restored.races.single.name, 'Test Grand Prix');
    offline.dispose();
  });

  testWidgets('home shows source-backed context for followed entries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({
      'followedDriverIds': jsonEncode([
        {'id': 'drv_norris', 'name': 'Lando Norris'},
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final repo = RaceRepository(
      preferences: preferences,
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/roster')
                ? {
                    'entries': [
                      {
                        'driver_id': 'drv_norris',
                        'driver': 'Lando Norris',
                        'team_id': 'tea_mclaren',
                        'team': 'McLaren',
                      },
                    ],
                    'source':
                        'https://api.jolpi.ca/ergast/f1/2030/driverstandings/',
                    'updated_at': '2030-09-13T00:00:00Z',
                    'stale': false,
                  }
                : {
                    'race': fixture(),
                    'stale': false,
                    'updated_at': '2030-09-13T00:00:00Z',
                  },
          ),
          200,
        ),
      ),
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      GrandPrixApp(repository: repo, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.text('本赛季关注'), findsOneWidget);
    expect(find.text('Lando Norris · McLaren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('countdown stops at zero and preserves elapsed-day arithmetic', () {
    final now = DateTime.utc(2030, 1, 1);
    expect(
      countdownLabel(
        now.add(const Duration(days: 2, hours: 3, minutes: 4)),
        now,
      ),
      '2d  3h  4m',
    );
    expect(countdownLabel(now, now), 'Scheduled start reached');
    expect(
      countdownLabel(now.subtract(const Duration(seconds: 1)), now),
      'Scheduled start reached',
    );
    expect(Race(fixture()).startsAt!.toUtc(), DateTime.utc(2030, 9, 15, 12));
    final summarized = Race({
      ...fixture(),
      'summary': {
        'winner': 'Test Winner',
        'winner_team': 'Test Team',
        'fastest_lap_driver': 'Quick Driver',
        'fastest_lap_time': '1:20.000',
        'fastest_lap_number': 42,
      },
    });
    expect(summarized.summary!.winner, 'Test Winner');
    expect(summarized.summary!.fastestLapNumber, 42);
  });

  for (final size in [
    const Size(320, 720),
    const Size(375, 812),
    const Size(812, 375),
    const Size(1024, 768),
  ]) {
    testWidgets('navigation and primary content at $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final repo = RaceRepository(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/seasons')
                  ? [2030, 2029, DateTime.now().year]
                  : {
                      if (request.url.path.endsWith('next-race'))
                        'race': fixture()
                      else
                        'races': [fixture()],
                      'stale': false,
                      'updated_at': '2030-09-13T00:00:00Z',
                    },
            ),
            200,
          ),
        ),
      );
      addTearDown(repo.dispose);
      await tester.pumpWidget(GrandPrixApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('TEST GRAND PRIX'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('赛历').last);
      await tester.pumpAndSettle();
      expect(find.text('赛季'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('首页').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看全部'));
      await tester.tap(find.text('查看全部'));
      await tester.pumpAndSettle();
      expect(find.text('暂无已结束的比赛可供查看赛后简报。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('TEST GRAND PRIX'), findsOneWidget);
    });
  }

  testWidgets('error offers retry and recovers to empty state', (tester) async {
    var calls = 0;
    final repo = RaceRepository(
      client: MockClient((_) async {
        if (calls++ == 0) return http.Response('unavailable', 503);
        return http.Response(
          jsonEncode({
            'race': null,
            'stale': false,
            'updated_at': '2030-09-13T00:00:00Z',
          }),
          200,
        );
      }),
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(GrandPrixApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('无法加载赛事'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无已公布的赛事'), findsOneWidget);
  });

  testWidgets(
    'follows the system language, switches immediately and restores preference',
    (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      var requests = 0;
      final repo = RaceRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('next-race')) requests++;
          return http.Response(
            jsonEncode({
              'race': {...fixture(), 'name': 'Azerbaijan Grand Prix'},
              'stale': false,
              'updated_at': '2030-09-13T00:00:00Z',
            }),
            200,
          );
        }),
      );
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        GrandPrixApp(repository: repo, preferences: preferences),
      );
      await tester.pumpAndSettle();
      expect(find.text('下一站大奖赛'), findsOneWidget);
      expect(find.text('阿塞拜疆大奖赛'), findsOneWidget);
      expect(
        Localizations.localeOf(tester.element(find.text('下一站大奖赛')))
            .languageCode,
        'zh',
      );
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      expect(find.text('NEXT GRAND PRIX'), findsOneWidget);
      expect(find.text('AZERBAIJAN GRAND PRIX'), findsOneWidget);
      expect(preferences.getString('language'), 'en');
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        GrandPrixApp(repository: repo, preferences: preferences),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      expect(find.text('NEXT GRAND PRIX'), findsOneWidget);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simplified Chinese').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('首页').last);
      await tester.pumpAndSettle();
      expect(find.text('下一站大奖赛'), findsOneWidget);
      expect(preferences.getString('language'), 'zh-CN');
    },
  );

  testWidgets('system Chinese requests localized Briefing content', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final requestedLanguages = <String?>[];
    final repo = RaceRepository(
      client: MockClient((request) async {
        final path = request.url.path;
        late final Map<String, dynamic> body;
        if (path.endsWith('/briefing')) {
          final language = request.url.queryParameters['lang'];
          requestedLanguages.add(language);
          body = {
            'race_id': '2026-14',
            'insights': [
              {
                'topic': 'Tyre issues',
                'detail': language == 'zh-CN'
                    ? '硬胎退化较低。'
                    : 'The hard tyre degraded slowly.',
                'sources': [],
              },
            ],
            'updated_at': '2026-06-14T12:00:00Z',
          };
        } else if (path.endsWith('/races')) {
          body = {
            'races': [
              {
                ...fixture(),
                'id': '2026-14',
                'name': 'Spanish Grand Prix',
                'date': '2026-06-14',
                'lifecycle_phase': 'post_race',
              },
            ],
            'stale': false,
            'updated_at': '2026-06-14T12:00:00Z',
          };
        } else {
          body = {
            'race': null,
            'stale': false,
            'updated_at': '2026-06-14T12:00:00Z',
          };
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(repo.dispose);

    await tester.pumpWidget(
      GrandPrixApp(repository: repo, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看全部'));
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();

    expect(requestedLanguages, everyElement('zh-CN'));
    expect(requestedLanguages, isNotEmpty);
    expect(find.text('硬胎退化较低。'), findsOneWidget);
  });
}
