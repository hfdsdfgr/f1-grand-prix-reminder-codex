import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grand_prix_reminder/data/race_repository.dart';
import 'package:grand_prix_reminder/data/reminder_service.dart';
import 'package:grand_prix_reminder/app.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:convert';

import 'app_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  final pending = <int, Map<String, dynamic>>{};
  var permission = true;
  var failSchedule = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    pending.clear();
    permission = true;
    failSchedule = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'requestNotificationsPermission' ||
              call.method == 'areNotificationsEnabled' ||
              call.method == 'canScheduleExactNotifications' ||
              call.method == 'requestExactAlarmsPermission') {
            return permission;
          }
          if (call.method == 'zonedSchedule' && failSchedule) {
            throw PlatformException(code: 'schedule_error');
          }
          if (call.method == 'zonedSchedule') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            pending[args['id'] as int] = args;
          }
          if (call.method == 'cancel') {
            pending.remove((call.arguments as Map)['id']);
          }
          if (call.method == 'pendingNotificationRequests') {
            return pending.values.toList();
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('stable IDs, UTC offset conversion and expired/custom validation', () {
    expect(reminderId('2026-15', 'Race'), reminderId('2026-15', 'Race'));
    expect(
      reminderId('2026-15', 'Race'),
      isNot(reminderId('2026-15', 'Qualifying')),
    );
    expect(reminderId('2026-15', 'Race'), isNot(reminderId('2026-16', 'Race')));
    final start = DateTime.parse('2030-03-31T14:00:00+02:00');
    final now = DateTime.utc(2030, 3, 30);
    expect(reminderTime(start, 60, now), DateTime.utc(2030, 3, 31, 11));
    for (final minutes in [0, -1, 10081]) {
      expect(
        () => reminderTime(start, minutes, now),
        throwsA(isA<ReminderException>()),
      );
    }
    expect(
      () => reminderTime(start, 60, start),
      throwsA(isA<ReminderException>()),
    );
  });

  test(
    'schedules UTC with stable ID, replaces and cancels only its own reminder',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ReminderService(prefs);
      final race = Race(fixture());
      await service.save(race, race.sessions.first, 60, 'zh');
      final scheduled =
          calls.firstWhere((c) => c.method == 'zonedSchedule').arguments as Map;
      expect(scheduled['id'], reminderId(race.id, 'Race'));
      expect(scheduled['timeZoneName'], 'Etc/UTC');
      expect(service.saved(race.id, 'Race')!['minutes'], 60);
      await service.save(race, race.sessions.first, 15, 'en');
      expect(service.saved(race.id, 'Race')!['minutes'], 15);
      expect(calls.where((c) => c.method == 'initialize').length, 1);
      await service.cancel(race.id, 'Race');
      expect(service.saved(race.id, 'Race'), isNull);
      expect(calls.any((c) => c.method == 'cancel'), isTrue);
      expect(calls.any((c) => c.method == 'cancelAll'), isFalse);
    },
  );

  test('permission and native failures never save a new reminder', () async {
    final service = ReminderService(await SharedPreferences.getInstance());
    final race = Race(fixture());
    permission = false;
    await expectLater(
      service.save(race, race.sessions.first, 15, 'zh'),
      throwsA(isA<ReminderException>()),
    );
    expect(calls.any((c) => c.method == 'zonedSchedule'), isFalse);
    expect(service.saved(race.id, 'Race'), isNull);
    permission = true;
    failSchedule = true;
    await expectLater(
      service.save(race, race.sessions.first, 15, 'zh'),
      throwsA(isA<PlatformException>()),
    );
    expect(service.saved(race.id, 'Race'), isNull);
  });

  test('automatic reminders default on and survive race completion, restart and offline', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = ReminderService(prefs);
    expect(service.automaticEnabled, isTrue);
    final clock = DateTime.utc(2030, 7, 1);
    Map<String, dynamic> race(String id, String start) => {
      ...fixture(),
      'id': id,
      'starts_at': start,
      'sessions': [
        {'kind': 'Race', 'starts_at': start},
      ],
    };
    final first = race('2030-1', '2030-07-02T12:00:00Z');
    final second = race('2030-2', '2030-07-09T12:00:00Z');
    var nextYear = race('2031-1', '2031-03-01T12:00:00Z');
    var offline = false;
    final repo = RaceRepository(
      client: MockClient(
        (request) async => offline
            ? http.Response('', 503)
            : http.Response(
                jsonEncode({
                  'races': request.url.queryParameters['season'] == '2030'
                      ? [first, second]
                      : [nextYear],
                  'updated_at': clock.toIso8601String(),
                  'stale': false,
                }),
                200,
              ),
      ),
    );
    addTearDown(repo.dispose);
    await service.syncUpcoming(repo, 'zh', now: clock);
    expect(service.syncMessage, isNull);
    expect(pending.keys.toSet(), {
      reminderId('2030-1', 'Race'),
      reminderId('2030-2', 'Race'),
      reminderId('2031-1', 'Race'),
    });
    expect(service.scheduledRaces, 3);
    // Future races are already registered with the OS before the first race ends.
    final restarted = ReminderService(prefs);
    await restarted.syncUpcoming(
      repo,
      'zh',
      now: clock.add(const Duration(days: 3)),
    );
    expect(pending.containsKey(reminderId('2030-1', 'Race')), isFalse);
    expect(pending.containsKey(reminderId('2030-2', 'Race')), isTrue);
    expect(
      calls.where((c) => c.method == 'requestNotificationsPermission').length,
      1,
    );
    expect(calls.where((c) => c.method == 'zonedSchedule').length, 3);
    nextYear = race('2031-1', '2031-03-03T12:00:00Z');
    await restarted.syncUpcoming(
      repo,
      'zh',
      now: clock.add(const Duration(days: 3)),
    );
    expect(
      restarted.saved('2031-1', 'Race')!['start'],
      '2031-03-03T12:00:00.000Z',
    );
    await restarted.cancel('2030-2', 'Race');
    await restarted.syncUpcoming(
      repo,
      'zh',
      now: clock.add(const Duration(days: 3)),
    );
    expect(pending.containsKey(reminderId('2030-2', 'Race')), isFalse);
    offline = true;
    await restarted.syncUpcoming(
      repo,
      'zh',
      now: clock.add(const Duration(days: 3)),
    );
    expect(pending.containsKey(reminderId('2031-1', 'Race')), isTrue);
    expect(restarted.syncMessage, contains('Existing reminders are kept'));
    await restarted.setAutomatic(false);
    expect(restarted.automaticEnabled, isFalse);
    expect(pending, isEmpty);
  });

  testWidgets('unsupported platform explains restriction and disables saving', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final repo = RaceRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'race': fixture(),
            'updated_at': '2030-09-13T00:00:00Z',
            'stale': false,
          }),
          200,
        ),
      ),
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      GrandPrixApp(
        repository: repo,
        preferences: await SharedPreferences.getInstance(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('赛事提醒'));
    await tester.tap(find.text('赛事提醒'));
    await tester.pumpAndSettle();
    expect(find.textContaining('系统本地提醒仅支持'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存提醒'),
    );
    expect(button.onPressed, isNull);
    expect(calls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });
}
