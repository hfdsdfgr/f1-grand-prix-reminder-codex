import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/core/theme.dart';
import 'package:grand_prix_reminder/features/evolution/car_model.dart';
import 'package:grand_prix_reminder/features/evolution/car_viewer.dart';

final canvas = find.byKey(const ValueKey('car-canvas'));
CarPainter painter(WidgetTester t) =>
    t.widget<CustomPaint>(canvas).painter! as CarPainter;

Future<void> showCar(
  WidgetTester t, {
  String language = 'en',
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 1000);
  await t.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: raceTheme(brightness).copyWith(
        textTheme: raceTheme(brightness).textTheme.apply(
          fontFamily: Platform.environment['CAR_PREVIEW_FONT'] == null
              ? null
              : 'PreviewFont',
        ),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1000),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('screen'),
            child: Material(
              color: raceTheme(brightness).colorScheme.surface,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CarViewer(key: UniqueKey(), enableGltf: false),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 100 && !t.any(canvas); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }
  expect(canvas, findsOneWidget);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Optional local fonts for readable screenshots; never bundled into the app.
    final path = Platform.environment['CAR_PREVIEW_FONT'];
    if (path != null) {
      final loader = FontLoader(
        'PreviewFont',
      )..addFont(File(path).readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '../.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
    }
  });
  test(
    'packaged geometry matches approved component count and faces',
    () async {
      final model = await CarModel.load();
      expect(model.components.length, 13);
      expect(model.components.map((c) => c.id).toSet().length, 13);
      expect(model.components.fold<int>(0, (s, c) => s + c.faces.length), 900);
      expect(model.materials.length, 5);
      expect(model.archives.length, 4);
      expect(
        model.archives.every((car) => car['base_3d_model_id'] == null),
        isTrue,
      );
      expect(
        model.archives
            .where((car) => car['team'] == 'redbull')
            .map((car) => car['name']),
        ['RB19', 'RB20', 'RB21'],
      );
      for (final c in model.components) {
        expect(c.text(true).length, 4);
        expect(c.text(false).length, 4);
        for (final f in c.faces) {
          expect(f.light.isFinite, isTrue);
          for (final p in f.points) {
            expect(p.$1.isFinite && p.$2.isFinite && p.$3.isFinite, isTrue);
          }
        }
      }
    },
  );

  testWidgets('native gestures, keyboard, presets and 13 component details', (
    t,
  ) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await showCar(t, brightness: Brightness.dark);
    final start = painter(t).yaw;
    await t.drag(canvas, const Offset(70, 20));
    await t.pump();
    expect(painter(t).yaw, isNot(start));
    // Once Flutter's gesture arena resolves, preserve the exact HTML delta.
    final gesture = await t.startGesture(t.getCenter(canvas));
    await gesture.moveBy(const Offset(30, 0));
    await t.pump();
    final before = painter(t).yaw;
    await gesture.moveBy(const Offset(20, 10));
    await t.pump();
    expect(painter(t).yaw, closeTo(before + .2, 1e-6));
    await gesture.up();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(painter(t).yaw, closeTo(before + .3, 1e-6));
    final oldZoom = painter(t).zoom;
    await t.sendEventToBinding(
      PointerScrollEvent(
        position: t.getCenter(canvas),
        scrollDelta: const Offset(0, -100),
      ),
    );
    await t.pump();
    expect(painter(t).zoom, closeTo(oldZoom * math.exp(.1), 1e-6));
    final center = t.getCenter(canvas);
    final a = await t.startGesture(center - const Offset(40, 0), pointer: 1);
    final b = await t.startGesture(center + const Offset(40, 0), pointer: 2);
    await a.moveBy(const Offset(-20, 0));
    await b.moveBy(const Offset(20, 0));
    await t.pump();
    expect(painter(t).zoom, greaterThan(oldZoom));
    await a.up();
    await b.up();
    for (final id in painter(t).model.components.map((c) => c.id).toList()) {
      final select = t.widget<DropdownButtonFormField<String>>(
        find.byKey(ValueKey('component-${painter(t).selected}')),
      );
      select.onChanged!(id);
      await t.pumpAndSettle();
      expect(painter(t).selected, id);
      expect(find.text(id), findsOneWidget);
    }
    await t.ensureVisible(find.text('Reset view'));
    await t.tap(find.text('Reset view'));
    await t.pump();
    expect(painter(t).yaw, -.65);
    expect(painter(t).pitch, .55);
    expect(painter(t).zoom, 1);
    expect(find.text('Power Unit'), findsNothing);
    await t.ensureVisible(find.byKey(const ValueKey('focus-mode')));
    await t.tap(find.byKey(const ValueKey('focus-mode')));
    await t.pumpAndSettle();
    expect(painter(t).focus, 1);
    await t.tap(find.byKey(const ValueKey('exploded-mode')));
    await t.pumpAndSettle();
    expect(painter(t).exploded, 1);
    await t.tap(find.byKey(const ValueKey('technical-mode')));
    await t.pump();
    expect(painter(t).technical, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('archive links are gated and browser errors stay in the app', (
    t,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return false;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await showCar(t);
    expect(find.text('Official Car'), findsNothing);
    await t.tap(find.text('Ferrari'));
    await t.pumpAndSettle();
    t
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('archive-ferrari-generic')),
        )
        .onChanged!('prototype_ferrari_sf23');
    await t.pumpAndSettle();
    expect(find.text('Official Car'), findsOneWidget);
    await t.ensureVisible(find.text('Official Car'));
    await t.tap(find.text('Official Car'));
    await t.pumpAndSettle();
    expect(
      calls.single.arguments['url'],
      'https://www.ferrari.com/en-US/formula1/sf-23',
    );
    expect(find.text('Unable to open the official page.'), findsOneWidget);
    await t.ensureVisible(find.text('McLaren'));
    await t.tap(find.text('McLaren'));
    await t.pumpAndSettle();
    expect(find.text('Official Car'), findsNothing);
    expect(painter(t).team, 'mclaren');
    expect(t.takeException(), isNull);
  });

  testWidgets('generation compare uses sourced changes and gates ghost view', (
    t,
  ) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await showCar(t, brightness: Brightness.dark);
    await t.tap(find.text('Red Bull'));
    await t.pumpAndSettle();
    t
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('archive-redbull-generic')),
        )
        .onChanged!('red_bull_rb20');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('compare-mode')));
    await t.tap(find.byKey(const ValueKey('compare-mode')));
    await t.pumpAndSettle();
    expect(find.text('Generation Compare'), findsOneWidget);
    expect(find.text('2023 / RB19'), findsWidgets);
    expect(find.text('2024 / RB20'), findsWidgets);
    expect(
      find.textContaining(
        'The official team page identifies updated cooling and sidepods.',
      ),
      findsOneWidget,
    );
    final ghost = t.widget<SwitchListTile>(
      find.byKey(const ValueKey('ghost-compare')),
    );
    expect(ghost.onChanged, isNull);
    final sidepods = find.byKey(const ValueKey('compare-component-sidepods'));
    await t.ensureVisible(sidepods);
    await t.tap(sidepods);
    await t.pumpAndSettle();
    expect(painter(t).selected, 'sidepods');
    expect(painter(t).focus, 1);
    await t.ensureVisible(find.byKey(const ValueKey('heritage-redbull')));
    await t.tap(find.byKey(const ValueKey('heritage-redbull')));
    await t.pumpAndSettle();
    expect(find.text('RB19'), findsWidgets);
    expect(find.text('RB21'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('Chinese, English, dark and large text render without overflow', (
    t,
  ) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final sample in [
      ('zh', 390.0, 1.0, Brightness.light),
      ('en', 390.0, 1.0, Brightness.dark),
      ('zh', 320.0, 2.0, Brightness.light),
    ]) {
      await showCar(
        t,
        language: sample.$1,
        width: sample.$2,
        scale: sample.$3,
        brightness: sample.$4,
      );
      await t.ensureVisible(canvas);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('screen')),
      );
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '../.tools/evolution-native/${sample.$1}-${sample.$2}-${sample.$4.name}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
