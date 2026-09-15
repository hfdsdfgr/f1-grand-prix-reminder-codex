import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/features/evolution/car_viewer.dart';

void main() {
  testWidgets('car supports gestures, internal selection, focus and reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CarViewer())),
      ),
    );
    final canvas = find
        .descendant(
          of: find.byType(CarViewer),
          matching: find.byType(CustomPaint),
        )
        .first;
    await tester.drag(canvas, const Offset(70, 20));
    await tester.pump();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Power Unit').last);
    await tester.tap(find.text('Power Unit').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Internal component: use focus to inspect.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Focus component'));
    await tester.tap(find.text('Focus component'));
    await tester.pump();
    expect(find.text('Show whole car'), findsOneWidget);
    await tester.tap(find.text('Reset view'));
    await tester.pump();
    expect(find.text('Focus component'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
