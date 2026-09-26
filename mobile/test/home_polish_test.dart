import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grand_prix_reminder/core/theme.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
import 'package:grand_prix_reminder/data/reminder_service.dart';
import 'package:grand_prix_reminder/features/home/home_page.dart';
import 'package:grand_prix_reminder/features/home/reminder_controls.dart';
import 'package:grand_prix_reminder/features/home/reminder_row.dart';

import 'app_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <String>[];
  var notifications = true;
  var alarms = true;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    notifications = true;
    alarms = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'initialize' => true,
            'areNotificationsEnabled' => notifications,
            'canScheduleExactNotifications' => alarms,
            _ => null,
          };
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'reminder row reads actual permission and refreshes after resume',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      final race = Race(fixture());
      await prefs.setString(
        'reminder.${reminderId(race.id, 'Race')}',
        jsonEncode({'minutes': 30}),
      );
      final service = ReminderService(prefs);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderRow(race: race, service: service, stale: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Race · 30 minutes before start · Enabled'),
        findsOneWidget,
      );
      expect(find.text('Notifications allowed'), findsOneWidget);
      notifications = false;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(
        find.text('Race · 30 minutes before start · Not enabled'),
        findsOneWidget,
      );
      expect(
        find.text('Allow notifications in system settings, then retry.'),
        findsOneWidget,
      );
      notifications = true;
      alarms = false;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(
        find.text('Allow alarms and reminders in system settings, then retry.'),
        findsOneWidget,
      );
      expect(
        calls.where((c) => c.startsWith('request') || c == 'zonedSchedule'),
        isEmpty,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'automatic preference alone does not claim a scheduled reminder',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      final service = ReminderService(prefs);
      expect(service.automaticEnabled, isTrue);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderRow(
              race: Race(fixture()),
              service: service,
              stale: false,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Race · 1 hour before · Not enabled'), findsOneWidget);
      expect(find.text('Notifications allowed'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Home lower actions retain navigation and hide raw source and counters',
    (t) async {
      final repo = RaceRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/media')) {
            return http.Response('[]', 200);
          }
          return http.Response(
            jsonEncode({
              'race': fixture(),
              'races': [],
              'stale': false,
              'updated_at': '2030-09-13T00:00:00Z',
            }),
            200,
          );
        }),
      );
      addTearDown(repo.dispose);
      final service = ReminderService(await SharedPreferences.getInstance());
      await t.pumpWidget(
        MaterialApp(
          theme: raceTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomePage(repository: repo, reminders: service),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text(fixture()['source'] as String), findsNothing);
      expect(find.textContaining('Scheduled races'), findsNothing);
      final details = find.byKey(const ValueKey('home-details'));
      await t.ensureVisible(details);
      await t.tap(details);
      await t.pumpAndSettle();
      expect(find.text('Race details'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      final reminders = find.byKey(const ValueKey('home-reminders'));
      await t.ensureVisible(reminders);
      await t.tap(reminders);
      await t.pumpAndSettle();
      expect(find.byType(ReminderSheet), findsOneWidget);
      expect(t.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
