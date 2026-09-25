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
import 'package:grand_prix_reminder/features/evolution/car_viewer.dart';
import 'package:grand_prix_reminder/features/evolution/component_explorer.dart';
import 'package:grand_prix_reminder/shared/race_briefing_view.dart';
import 'package:grand_prix_reminder/shared/editorial_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '../.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    for (final entry in {
      'Newsreader': 'Newsreader.ttf',
      'Barlow': 'Barlow-Regular.ttf',
      'BarlowCondensed': 'BarlowCondensed-Regular.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File('assets/fonts/${entry.value}')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    }
  });

  testWidgets(
    'quotes require field evidence; original anchors remain accessible',
    (t) async {
      final repo = RaceRepository(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'race_id': '2026-1',
              'updated_at': '2026-01-01T00:00:00Z',
              'sources': [],
              'insights': [
                {
                  'topic': 'Key quotes',
                  'detail': 'Unsupported quote',
                  'field': 'key_quotes',
                  'sources': [],
                },
                {
                  'topic': 'Key quotes',
                  'detail': 'Verified summary',
                  'field': 'key_quotes',
                  'sources': [],
                  'evidence': [
                    {
                      'quote': 'Exact original passage',
                      'source': {
                        'provider': 'Test source',
                        'url': 'https://example.com/evidence',
                      },
                    },
                  ],
                },
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(repo.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceBriefingView(
              repository: repo,
              raceId: '2026-1',
              quotesOnly: true,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Unsupported quote'), findsNothing);
      expect(find.text('Verified summary'), findsNothing);
      await t.tap(find.text('Exact original passage'));
      await t.pumpAndSettle();
      expect(find.text('Exact original passage'), findsOneWidget);
      expect(find.text('https://example.com/evidence'), findsOneWidget);
    },
  );

  testWidgets('spoiler media never creates an image or exposes its caption', (
    t,
  ) async {
    final repo = RaceRepository(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode([
            {
              'id': 'photo',
              'role': 'briefing',
              'url': 'https://example.com/winner.jpg',
              'source_url': 'https://example.com/report',
              'credit': 'Photographer',
              'license': 'Test license',
              'caption': 'Result revealed in caption',
              'spoiler': true,
            },
          ]),
          200,
        ),
      ),
    );
    addTearDown(repo.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorialMediaView(
            repository: repo,
            raceId: '2026-1',
            role: 'briefing',
            spoilerHidden: true,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.bySemanticsLabel('Result revealed in caption'), findsNothing);
  });

  testWidgets(
    'component detail keeps unknown claims and fullscreen retains camera',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final entry = UpgradeEntry({
        'id': 'test-floor',
        'team_id': 'cadillac',
        'team': 'Test team',
        'component_id': 'floor',
        'component': 'Floor',
        'title': 'Test evidence record',
        'status': 'tested',
        'confidence': null,
        'race_id': '2026-1',
        'race': 'Test Grand Prix',
        'change': 'Source-backed test change.',
        'goal': null,
        'sources': [
          {'provider': 'Test source', 'url': 'https://example.com/update'},
        ],
      });
      await t.pumpWidget(
        MaterialApp(
          theme: raceTheme(Brightness.dark),
          home: RepaintBoundary(
            key: const ValueKey('explorer-preview'),
            child: ComponentExplorer(
              entries: [entry],
              initialId: entry.id,
              enableGltf: false,
            ),
          ),
        ),
      );
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
      expect(find.text('Unknown'), findsNWidgets(2));
      expect(find.text('Source-backed test change.'), findsOneWidget);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('explorer-preview')),
      );
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../.tools/f1-preview/explorer.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await t.ensureVisible(find.byTooltip('Fullscreen'));
      await t.tap(find.byTooltip('Fullscreen'));
      await t.pumpAndSettle();
      CarPainter painter() =>
          t
                  .widget<CustomPaint>(find.byKey(const ValueKey('car-canvas')))
                  .painter!
              as CarPainter;
      final before = painter().yaw;
      await t.drag(
        find.byKey(const ValueKey('car-gesture')),
        const Offset(40, 0),
      );
      await t.pumpAndSettle();
      final after = painter().yaw;
      expect(after, isNot(before));
      await t.tap(find.byType(CloseButton));
      await t.pumpAndSettle();
      expect(painter().yaw, after);
      expect(painter().selected, 'floor');
      expect(t.takeException(), isNull);
    },
  );
}
