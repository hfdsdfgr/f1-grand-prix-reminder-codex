import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grand_prix_reminder/core/theme.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
import 'package:grand_prix_reminder/features/home/home_page.dart';
import 'package:grand_prix_reminder/features/home/reminder_controls.dart';
import 'package:grand_prix_reminder/features/races/races_page.dart';
import 'package:grand_prix_reminder/features/races/race_detail_page.dart';
import 'package:grand_prix_reminder/features/settings/settings_page.dart';
import 'package:grand_prix_reminder/features/evolution/evolution_page.dart';
import 'package:grand_prix_reminder/shared/race_briefing_view.dart';

import 'app_test.dart' show fixture;
import 'race_detail_test.dart'
    show
        completedRace,
        resultFeed,
        storyFeed,
        strategyFeed,
        championshipImpactFeed;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final icons = File(
      '../.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
    }
    for (final font in ['Newsreader', 'BarlowCondensed', 'Barlow']) {
      final path = font == 'Newsreader'
          ? 'assets/fonts/Newsreader.ttf'
          : 'assets/fonts/$font-Regular.ttf';
      await (FontLoader(
        font,
      )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
    }
    final font = File(
      '../.tools/flutter/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
    );
    if (font.existsSync()) {
      await (FontLoader(
        'PreviewFont',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  for (final sample in [(390.0, 1.0), (320.0, 1.6), (812.0, 1.6)]) {
    testWidgets(
      'F1 sections and long evidence at ${sample.$1}px scale ${sample.$2}',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(sample.$1, sample.$1 == 812 ? 375 : 844);
        t.platformDispatcher.textScaleFactorTestValue = sample.$2;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final repo = RaceRepository(
          client: MockClient((request) async {
            final path = request.url.path;
            final dynamic data;
            if (path.endsWith('/seasons')) {
              data = [DateTime.now().year];
            } else if (path.endsWith('/results')) {
              data = resultFeed();
            } else if (path.endsWith('/story')) {
              data = storyFeed();
            } else if (path.endsWith('/strategy')) {
              data = strategyFeed();
            } else if (path.endsWith('/championship-impact')) {
              data = championshipImpactFeed();
            } else if (path.contains('/evolution')) {
              data = {'upgrades': [], 'timeline': []};
            } else if (path.endsWith('/briefing')) {
              data = {
                'race_id': '2030-1',
                'insights': [
                  {
                    'topic': 'Driver feedback',
                    'detail': 'Test driver feedback with a long technical explanation to verify readable wrapping at enlarged system font sizes.',
                    'sources': [
                      {
                        'provider': 'Official team race report',
                        'url': 'https://example.com/official-race-report-with-a-long-source-reference',
                      },
                    ],
                  },
                ],
                'sources': [],
                'stale': false,
                'updated_at': '2030-09-13T00:00:00Z',
              };
            } else {
              data = {
                'race': fixture(),
                'races': [
                  fixture(),
                  {...completedRace(), 'id': '2030-2'},
                ],
                'stale': false,
                'updated_at': '2030-09-13T00:00:00Z',
              };
            }
            return http.Response(jsonEncode(data), 200);
          }),
        );
        addTearDown(repo.dispose);
        final pages = <String, Widget>{
          'home': HomePage(repository: repo),
          'calendar': RacesPage(repository: repo),
          'briefing': RaceBriefingView(repository: repo, raceId: '2030-1'),
          'evolution': EvolutionPage(
            repository: repo,
            enableGltf: false,
            raceId: '2030-1',
          ),
          'reminder': ReminderSheet(race: Race(fixture()), stale: false),
          'settings': SettingsPage(
            spoilerFree: true,
            onSpoilerFreeChanged: (_) {},
          ),
          'results': RaceDetailPage(
            race: Race(completedRace()),
            repository: repo,
          ),
        };
        for (final entry in pages.entries) {
          final standalone = ['settings', 'results'].contains(entry.key);
          await t.pumpWidget(
            MaterialApp(
              theme: raceTheme(Brightness.dark),
              home: RepaintBoundary(
                key: const ValueKey('f1-screen'),
                child: standalone
                    ? entry.value
                    : Scaffold(
                        body: SingleChildScrollView(
                          padding: RaceSpace.page,
                          child: entry.value,
                        ),
                      ),
              ),
            ),
          );
          if (entry.key == 'evolution') {
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
          }
          if (entry.key == 'evolution') {
            await t.pump(const Duration(milliseconds: 300));
          } else {
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull, reason: entry.key);
          if (entry.key == 'briefing') {
            expect(find.text('DRIVER FEEDBACK'), findsOneWidget);
          }
          if (entry.key == 'results') {
            expect(find.text('1. Test Driver'), findsOneWidget);
          }
          if (sample.$2 == 1) {
            final boundary = t.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('f1-screen')),
            );
            await t.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('../.tools/f1-preview/${entry.key}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await t.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}
