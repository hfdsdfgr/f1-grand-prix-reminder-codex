import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grand_prix_reminder/core/theme.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
import 'package:grand_prix_reminder/features/evolution/evolution_page.dart';
import 'package:grand_prix_reminder/features/evolution/component_explorer.dart';
import 'package:grand_prix_reminder/features/evolution/car_model.dart';
import 'package:grand_prix_reminder/l10n/app_localizations.dart';

Future<void> waitForCar(WidgetTester t) async {
  for (
    var i = 0;
    i < 100 && !t.any(find.byKey(const ValueKey('car-canvas')));
    i++
  ) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }
  await t.pumpAndSettle();
  expect(find.byKey(const ValueKey('car-canvas')), findsOneWidget);
  expect(t.takeException(), isNull);
}

void main() {
  setUp(() => rootBundle.clear());
  for (final language in ['en', 'zh-CN']) {
    testWidgets('real Evolution payload restores scroll in $language', (
      t,
    ) async {
      final payload = File('test/fixtures/evolution/2026-$language.json')
          .readAsStringSync();
      final repository = RaceRepository(
        language: language,
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(payload),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final feed = EvolutionFeed(jsonDecode(payload) as Map<String, dynamic>);
      expect(feed.upgrades, hasLength(42));
      expect(feed.stale, isFalse);
      addTearDown(repository.dispose);
      final bucket = PageStorageBucket();
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget page(bool visible) => MaterialApp(
        theme: raceTheme(Brightness.dark),
        locale: language == 'en'
            ? const Locale('en')
            : const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: visible
                ? SingleChildScrollView(
                    key: const PageStorageKey('page-2'),
                    controller: controller,
                    child: EvolutionPage(
                      repository: repository,
                      enableGltf: false,
                    ),
                  )
                : const SizedBox(),
          ),
        ),
      );
      await t.pumpWidget(page(true));
      await waitForCar(t);
      expect(find.byType(ExpansionTile), findsWidgets);
      controller.jumpTo(120);
      await t.pumpAndSettle();
      await t.pumpWidget(page(false));
      await t.pumpWidget(page(true));
      await waitForCar(t);
      final archive = find.byKey(const PageStorageKey('car-archive'));
      final tools = find.byKey(const PageStorageKey('car-tools'));
      await t.ensureVisible(archive);
      await t.tap(
        find.descendant(of: archive, matching: find.byType(ListTile)).first,
      );
      await t.pumpAndSettle();
      await t.pumpWidget(page(false));
      await t.pumpWidget(page(true));
      await waitForCar(t);
      expect(
        find.descendant(
          of: archive,
          matching: find.text(language == 'en' ? 'Explore the car' : '探索赛车'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tools, matching: find.byType(SwitchListTile)),
        findsNothing,
      );

      final refresh = find.widgetWithIcon(TextButton, Icons.refresh);
      await t.ensureVisible(refresh);
      await t.tap(refresh);
      await t.pumpAndSettle();
      await waitForCar(t);
    });

    for (final raceId in ['2026-1', '2026-22']) {
      testWidgets('real $raceId renders in $language', (t) async {
        final payload = File('test/fixtures/evolution/$raceId-$language.json')
            .readAsStringSync();
        final repo = RaceRepository(
          language: language,
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/evolution/$raceId');
            expect(request.url.queryParameters['lang'], language);
            return http.Response.bytes(
              utf8.encode(payload),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(repo.dispose);
        await t.pumpWidget(
          MaterialApp(
            theme: raceTheme(Brightness.dark),
            locale: language == 'en'
                ? const Locale('en')
                : const Locale('zh', 'CN'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                key: const PageStorageKey('page-2'),
                child: EvolutionPage(
                  repository: repo,
                  raceId: raceId,
                  enableGltf: false,
                ),
              ),
            ),
          ),
        );
        await waitForCar(t);
        if (raceId == '2026-22') {
          expect(
            find.text(
              language == 'en'
                  ? 'No recorded upgrades for this selection.'
                  : '当前所选范围暂无已记录的升级。',
            ),
            findsOneWidget,
          );
        } else {
          expect(
            find.byKey(const ValueKey('upg_1a2fc5cc2a2449db9acfb35ec5bae88a')),
            findsOneWidget,
          );
        }
      });
    }

    testWidgets('actual low confidence remains numeric evidence in $language', (
      t,
    ) async {
      final json = jsonDecode(
        File('test/fixtures/evolution/2026-$language.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final entry = EvolutionFeed(json).upgrades.firstWhere(
        (e) =>
            carComponentIds.contains(e.componentId) &&
            double.parse(e.confidence) < .75,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: raceTheme(Brightness.dark),
          locale: language == 'en'
              ? const Locale('en')
              : const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ComponentExplorer(
            entries: [entry],
            initialId: entry.id,
            enableGltf: false,
          ),
        ),
      );
      await waitForCar(t);
      final value = '${language == 'en' ? 'Low' : '低'} · ${entry.confidence}';
      expect(find.text(value), findsOneWidget);
      for (final source in entry.sources) {
        expect(find.text(source.url), findsOneWidget);
      }
    });
  }
  test('historical empty season retains the API contract', () {
    for (final language in ['en', 'zh-CN']) {
      final json = jsonDecode(
        File('test/fixtures/evolution/2025-$language.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['stale'], isA<bool>());
      final feed = EvolutionFeed(json);
      expect(feed.upgrades, isEmpty);
      expect(feed.timeline, isEmpty);
    }
  });
}
