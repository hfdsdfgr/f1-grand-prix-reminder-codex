import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/language.dart';
import 'race_repository.dart';

const reminderKinds = ['Race', 'Qualifying', 'Sprint'];

int reminderId(String raceId, String kind) {
  final parts = raceId.split('-').map(int.parse).toList();
  final index = reminderKinds.indexOf(kind);
  if (parts.length != 2 ||
      index < 0 ||
      parts[0] < 1950 ||
      parts[0] > 2100 ||
      parts[1] < 1 ||
      parts[1] > 99) {
    throw ArgumentError('Invalid reminder identity');
  }
  return parts[0] * 1000 + parts[1] * 10 + index;
}

DateTime reminderTime(DateTime start, int minutes, DateTime now) {
  if (minutes < 1 || minutes > 10080) {
    throw const ReminderException('Choose 1 to 10080 minutes.');
  }
  final time = start.toUtc().subtract(Duration(minutes: minutes));
  if (!time.isAfter(now.toUtc())) {
    throw const ReminderException('This reminder time has already passed.');
  }
  return time;
}

class ReminderException implements Exception {
  final String message;
  const ReminderException(this.message);
}

class ReminderService {
  final SharedPreferences preferences;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void> _queue = Future.value();
  String? syncMessage;
  int scheduledRaces = 0;
  ReminderService(this.preferences);

  bool get automaticEnabled =>
      preferences.getBool('automaticRaceReminders') ?? true;

  Future<void> _exclusive(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String _key(int id) => 'reminder.$id';

  Map<String, dynamic>? saved(String raceId, String kind) {
    final value = preferences.getString(_key(reminderId(raceId, kind)));
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<void> _initialize() async {
    if (!supported) {
      throw const ReminderException(
        'Local reminders are available in the Android and iOS apps.',
      );
    }
    if (_ready) return;
    final ready = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (ready != true) {
      throw const ReminderException('Unable to initialize notifications.');
    }
    _ready = true;
  }

  Future<void> _permissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      if (await android.requestNotificationsPermission() != true) {
        throw const ReminderException(
          'Allow notifications in system settings, then retry.',
        );
      }
      if (await android.canScheduleExactNotifications() != true &&
          await android.requestExactAlarmsPermission() != true) {
        throw const ReminderException(
          'Allow alarms and reminders in system settings, then retry.',
        );
      }
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null &&
        await ios.requestPermissions(alert: true, sound: true, badge: false) !=
            true) {
      throw const ReminderException(
        'Allow notifications in system settings, then retry.',
      );
    }
  }

  Future<void> save(
    Race race,
    RaceSession session,
    int minutes,
    String language,
  ) => _exclusive(() => _save(race, session, minutes, language));

  Future<void> _save(
    Race race,
    RaceSession session,
    int minutes,
    String language, {
    bool automatic = false,
    bool requestPermissions = true,
  }) async {
    final id = reminderId(race.id, session.kind);
    if (session.startsAt == null) {
      throw const ReminderException('Session time is not available.');
    }
    reminderTime(session.startsAt!, minutes, DateTime.now());
    await _initialize();
    if (requestPermissions) await _permissions();
    // Recheck after system permission dialogs; those may have stayed open.
    final time = reminderTime(session.startsAt!, minutes, DateTime.now());
    final record = {
      'start': session.startsAt!.toUtc().toIso8601String(),
      'minutes': minutes,
      'raceId': race.id,
      'raceInternalId': race.internalId,
      'sessionId': session.internalId,
      'kind': session.kind,
      'automatic': automatic,
      'title': translate(language, race.name),
      'body':
          '${translate(language, session.kind)} · ${translate(language, 'Starts in')} $minutes ${translate(language, 'minutes')}',
    };
    await _plugin.zonedSchedule(
      id: id,
      title: record['title'] as String,
      body: record['body'] as String,
      scheduledDate: tz.TZDateTime.from(time, tz.UTC),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'race_reminders',
          'Race reminders',
          channelDescription: 'Scheduled Formula 1 sessions',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: race.id,
    );
    try {
      if (!await preferences.setString(_key(id), jsonEncode(record))) {
        throw const ReminderException('Unable to save reminder. Please retry.');
      }
      await preferences.remove('reminderSuppressed.$id');
    } catch (_) {
      await _plugin.cancel(id: id);
      await preferences.remove(_key(id));
      throw const ReminderException('Unable to save reminder. Please retry.');
    }
  }

  Future<void> cancel(String raceId, String kind) async {
    return _exclusive(() async {
      await _initialize();
      final id = reminderId(raceId, kind);
      // Remember explicit opt-outs so the next automatic sync does not undo them.
      if (!await preferences.setBool('reminderSuppressed.$id', true)) {
        throw const ReminderException('Unable to save reminder. Please retry.');
      }
      await _plugin.cancel(id: id);
      if (!await preferences.remove(_key(id))) {
        throw const ReminderException('Unable to save reminder. Please retry.');
      }
    });
  }

  Map<int, Map<String, dynamic>> get _records => {
    for (final key in preferences.getKeys().where(
      (k) => k.startsWith('reminder.'),
    ))
      int.parse(key.substring('reminder.'.length)):
          jsonDecode(preferences.getString(key)!) as Map<String, dynamic>,
  };

  Future<void> setAutomatic(bool enabled) => _exclusive(() async {
    if (!await preferences.setBool('automaticRaceReminders', enabled)) {
      throw const ReminderException('Unable to save reminder. Please retry.');
    }
    if (!enabled && supported) {
      await _initialize();
      for (final entry in _records.entries.where(
        (e) => e.value['automatic'] == true,
      )) {
        await _plugin.cancel(id: entry.key);
        await preferences.remove(_key(entry.key));
      }
      scheduledRaces = 0;
    }
  });

  /// Read system permission state without requesting access or scheduling.
  Future<String?> permissionIssue() async {
    try {
      await _initialize();
      await _checkPermissions();
      return null;
    } on ReminderException catch (error) {
      return error.message;
    }
  }

  Future<void> _checkPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      if (await android.areNotificationsEnabled() != true) {
        throw const ReminderException(
          'Allow notifications in system settings, then retry.',
        );
      }
      if (await android.canScheduleExactNotifications() != true) {
        throw const ReminderException(
          'Allow alarms and reminders in system settings, then retry.',
        );
      }
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null && (await ios.checkPermissions())?.isEnabled != true) {
      throw const ReminderException(
        'Allow notifications in system settings, then retry.',
      );
    }
  }

  Future<void> syncUpcoming(
    RaceRepository repository,
    String language, {
    bool requestPermissions = false,
    DateTime? now,
  }) => _exclusive(() async {
    if (!supported) return;
    syncMessage = null;
    try {
      await _initialize();
      if (!automaticEnabled && _records.isEmpty) return;
      if (requestPermissions ||
          !(preferences.getBool('reminderPermissionAsked') ?? false)) {
        await preferences.setBool('reminderPermissionAsked', true);
        await _permissions();
      } else {
        await _checkPermissions();
      }
      final clock = now ?? DateTime.now();
      // Fetch seasons independently: next season being unavailable must not
      // discard already scheduled reminders from this season.
      final seasons = [clock.year, clock.year + 1];
      final feeds = await Future.wait(
        seasons.map((season) async {
          try {
            return await repository.load(season: season, summaries: false);
          } catch (_) {
            return null;
          }
        }),
      );
      final freshYears = <int>{};
      final races = <Race>[];
      for (var i = 0; i < feeds.length; i++) {
        if (feeds[i] != null && !feeds[i]!.stale) {
          freshYears.add(seasons[i]);
          races.addAll(feeds[i]!.races);
        }
      }
      if (freshYears.isEmpty) {
        throw const ReminderException(
          'Could not refresh reminders. Existing reminders are kept.',
        );
      }
      final records = _records;
      final targets =
          <({Race race, RaceSession session, int minutes, bool automatic})>[];
      for (final race in races) {
        for (final session in race.sessions.where(
          (s) =>
              reminderKinds.contains(s.kind) &&
              s.startsAt != null &&
              s.status != 'cancelled' &&
              s.status != 'completed',
        )) {
          final id = reminderId(race.id, session.kind);
          if (preferences.getBool('reminderSuppressed.$id') == true) continue;
          final existing = records[id];
          final manual = existing != null && existing['automatic'] != true;
          if (!manual && !(automaticEnabled && session.kind == 'Race')) {
            continue;
          }
          final minutes = manual ? existing['minutes'] as int : 60;
          if (!session.startsAt!
              .subtract(Duration(minutes: minutes))
              .isAfter(clock)) {
            continue;
          }
          targets.add((
            race: race,
            session: session,
            minutes: minutes,
            automatic: !manual,
          ));
        }
      }
      targets.sort(
        (a, b) => a.session.startsAt!
            .subtract(Duration(minutes: a.minutes))
            .compareTo(
              b.session.startsAt!.subtract(Duration(minutes: b.minutes)),
            ),
      );
      final pending = (await _plugin.pendingNotificationRequests())
          .map((n) => n.id)
          .toSet();
      final desired = targets
          .map((t) => reminderId(t.race.id, t.session.kind))
          .toSet();
      for (final entry in records.entries) {
        final id = entry.key;
        final expired = !DateTime.parse(entry.value['start'] as String)
            .subtract(Duration(minutes: entry.value['minutes'] as int))
            .isAfter(clock);
        if (expired ||
            (freshYears.contains(id ~/ 1000) && !desired.contains(id))) {
          await _plugin.cancel(id: id);
          await preferences.remove(_key(id));
          pending.remove(id);
        }
      }
      // Stay below iOS's 64 pending notifications, including manual reminders
      // and records from a season whose network request failed.
      for (final target in targets) {
        final id = reminderId(target.race.id, target.session.kind);
        if (!pending.contains(id) && pending.length >= 60) break;
        final previous = records[id];
        final unchanged =
            previous != null &&
            pending.contains(id) &&
            previous['start'] ==
                target.session.startsAt!.toUtc().toIso8601String() &&
            previous['sessionId'] == target.session.internalId &&
            previous['minutes'] == target.minutes &&
            previous['title'] == translate(language, target.race.name) &&
            previous['body'] ==
                '${translate(language, target.session.kind)} · ${translate(language, 'Starts in')} ${target.minutes} ${translate(language, 'minutes')}';
        if (!unchanged) {
          await _save(
            target.race,
            target.session,
            target.minutes,
            language,
            automatic: target.automatic,
            requestPermissions: false,
          );
        }
        pending.add(id);
      }
      scheduledRaces = _records.entries
          .where((e) => e.key % 10 == 0 && pending.contains(e.key))
          .length;
      if (feeds.any((f) => f == null || f.stale)) {
        syncMessage = 'Some schedules could not be refreshed. Existing reminders are kept.';
      }
    } on ReminderException catch (error) {
      syncMessage = error.message;
    } catch (_) {
      syncMessage = 'Could not refresh reminders. Existing reminders are kept.';
    }
  });
}
