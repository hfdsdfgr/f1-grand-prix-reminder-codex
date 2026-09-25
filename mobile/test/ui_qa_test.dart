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
import 'package:grand_prix_reminder/features/briefing/briefing_page.dart';
import 'package:grand_prix_reminder/features/evolution/evolution_page.dart';
import 'package:grand_prix_reminder/features/races/races_page.dart';
import 'package:grand_prix_reminder/features/races/race_detail_page.dart';
import 'package:grand_prix_reminder/features/settings/settings_page.dart';
import 'package:grand_prix_reminder/l10n/app_localizations.dart';

import 'evolution_payload_test.dart' show waitForCar;

String captured(String name) =>
    File('test/fixtures/ui_qa/$name.json').readAsStringSync();

RaceRepository repository(String language) => RaceRepository(
  language: language,
  client: MockClient((request) async {
    final endpoint = request.url.path.split('/').last;
    final String body;
    if (endpoint == 'evolution') {
      body = File('test/fixtures/evolution/2026-$language.json')
          .readAsStringSync();
    } else {
      final lang = endpoint == 'briefing' ? language : 'en';
      body = captured('$endpoint-$lang');
    }
    return http.Response.bytes(
      utf8.encode(body),
      endpoint == 'media'
          ? 404
          : endpoint == 'strategy'
          ? 503
          : 200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

Widget app(Widget page, String language, {bool standalone = false}) {
  final theme = raceTheme(Brightness.dark);
  return MaterialApp(
    theme: theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamilyFallback: ['QA Chinese']),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'Barlow',
          fontFamilyFallback: ['QA Chinese'],
        ),
      ),
    ),
    locale: language == 'en' ? const Locale('en') : const Locale('zh', 'CN'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RepaintBoundary(
      key: const ValueKey('qa-screen'),
      child: standalone
          ? page
          : Scaffold(
              appBar: AppBar(toolbarHeight: 44),
              bottomNavigationBar: const SizedBox(height: 64),
              body: SingleChildScrollView(padding: RaceSpace.page, child: page),
            ),
    ),
  );
}

Future<void> capture(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('qa-screen')),
  );
  // Repaint the screenshot boundary after asynchronous assets settle.
  boundary.markNeedsPaint();
  await t.pump();
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../.tools/ui-qa/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    final fonts = {
      'Newsreader': 'assets/fonts/Newsreader.ttf',
      'Barlow': 'assets/fonts/Barlow-Regular.ttf',
      'BarlowCondensed': 'assets/fonts/BarlowCondensed-Regular.ttf',
      'MaterialIcons': '../.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      'QA Chinese': 'C:/Windows/Fonts/msyh.ttc',
    };
    for (final entry in fonts.entries) {
      final file = File(entry.value);
      if (file.existsSync()) {
        await (FontLoader(
          entry.key,
        )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });

  for (final language in ['en', 'zh-CN']) {
    testWidgets('Calendar order, density, spoilers and details in $language', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = repository(language);
      addTearDown(repo.dispose);
      var revealed = false;
      await t.pumpWidget(
        app(
          RacesPage(
            repository: repo,
            spoilerFree: true,
            onRevealSession: (_) => revealed = true,
          ),
          language,
        ),
      );
      await t.pumpAndSettle();
      List<String> order() => t
          .widgetList<InkWell>(
            find.byWidgetPredicate(
              (w) =>
                  w is InkWell &&
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith('calendar-'),
            ),
          )
          .map((w) => (w.key as ValueKey<String>).value)
          .toList();
      expect(order(), [
        for (var i = 15; i <= 23; i++) 'calendar-2026-$i',
        for (var i = 1; i <= 14; i++) 'calendar-2026-$i',
      ]);
      final rows = [
        for (var i = 15; i <= 23; i++)
          t.getRect(find.byKey(ValueKey('calendar-2026-$i'))),
      ];
      final visible = rows.where((r) => r.top >= 44 && r.bottom <= 780).length;
      expect(visible, inInclusiveRange(4, 5));
      expect(find.textContaining('George Russell'), findsNothing);
      expect(find.text(language == 'en' ? 'Fastest lap' : '最快圈'), findsNothing);
      await capture(t, 'calendar-upcoming-$language');
      await t.tap(find.byKey(const ValueKey('completed-first')));
      await t.pumpAndSettle();
      expect(order(), [
        for (var i = 1; i <= 14; i++) 'calendar-2026-$i',
        for (var i = 15; i <= 23; i++) 'calendar-2026-$i',
      ]);
      await capture(t, 'calendar-completed-$language');
      final row = find.byKey(const ValueKey('calendar-2026-14'));
      await t.ensureVisible(row);
      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.byType(RaceDetailPage), findsOneWidget);
      expect(find.textContaining('Andrea Kimi Antonelli'), findsNothing);
      final reveal = find.text(
        language == 'en' ? 'Reveal this session' : '揭晓本场',
      );
      await t.ensureVisible(reveal);
      await t.tap(reveal);
      await t.pumpAndSettle();
      expect(revealed, isTrue);
      expect(find.text(language == 'en' ? 'Fastest lap' : '最快圈'), findsWidgets);
      final results = ResultsFeed(
        jsonDecode(captured('results-en')) as Map<String, dynamic>,
      );
      expect(find.text(results.fastestLap!.time), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    for (final scale in [1.0, 1.6]) {
      testWidgets('real payload page QA $language scale $scale', (t) async {
        t.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final repo = repository(language);
        addTearDown(repo.dispose);
        final race = RaceFeed(
          jsonDecode(captured('races-en')) as Map<String, dynamic>,
        ).races.firstWhere((r) => r.id == '2026-14');
        final pages = {
          'calendar': RacesPage(repository: repo),
          'evolution': EvolutionPage(repository: repo, enableGltf: false),
          'briefing': BriefingPage(repository: repo, initialRaceId: race.id),
          'detail': RaceDetailPage(repository: repo, race: race),
          'settings': SettingsPage(
            spoilerFree: true,
            onSpoilerFreeChanged: (_) {},
            language: language,
            onLanguageChanged: (_) {},
          ),
        };
        for (final entry in pages.entries) {
          await t.pumpWidget(
            app(
              entry.value,
              language,
              standalone: ['detail', 'settings'].contains(entry.key),
            ),
          );
          if (entry.key == 'evolution') {
            await waitForCar(t);
          } else {
            await t.pumpAndSettle();
          }
          expect(
            t.takeException(),
            isNull,
            reason: '${entry.key} $language $scale',
          );
          expect(find.byType(ErrorWidget), findsNothing);
          if (scale == 1) await capture(t, '${entry.key}-$language');
          await t.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
