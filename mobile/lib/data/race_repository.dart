import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RaceSession {
  final String kind;
  final String? internalId;
  final String sessionType, displayName, status;
  final DateTime? startsAt;
  RaceSession(Map<String, dynamic> json)
    : kind = json['kind'] as String,
      internalId = json['internal_id'] as String?,
      sessionType = json['session_type'] as String? ?? 'other',
      displayName = json['display_name'] as String? ?? json['kind'] as String,
      status = json['status'] as String? ?? 'unknown',
      startsAt = json['starts_at'] == null
          ? null
          : DateTime.parse(json['starts_at'] as String).toLocal();
}

class RaceSummary {
  final String? winner, winnerTeam, fastestLapDriver, fastestLapTime;
  final int? fastestLapNumber;
  RaceSummary(Map<String, dynamic> json)
    : winner = json['winner'] as String?,
      winnerTeam = json['winner_team'] as String?,
      fastestLapDriver = json['fastest_lap_driver'] as String?,
      fastestLapTime = json['fastest_lap_time'] as String?,
      fastestLapNumber = json['fastest_lap_number'] as int?;
}

class CircuitLayout {
  final String id, assetPath, source, license;
  final int validFrom;
  final int? turns;
  CircuitLayout(Map<String, dynamic> json)
    : id = json['id'] as String,
      assetPath = json['asset_path'] as String,
      validFrom = json['valid_from'] as int,
      source = json['source'] as String,
      license = json['license'] as String,
      turns = json['turns'] as int?;
}

class Race {
  final String id, name, circuit, date, source;
  final int season;
  final String? internalId, circuitId;
  final String status;
  final String lifecyclePhase;
  final RaceSummary? summary;
  final CircuitLayout? circuitLayout;
  final RaceSession? currentSession, nextSession;
  final DateTime? countdownTarget;
  final DateTime? startsAt;
  final List<RaceSession> sessions;
  Race(Map<String, dynamic> json)
    : id = json['id'] as String,
      season =
          json['season'] as int? ?? DateTime.parse(json['date'] as String).year,
      internalId = json['internal_id'] as String?,
      circuitId = json['circuit_id'] as String?,
      status = json['status'] as String? ?? 'unknown',
      lifecyclePhase = json['lifecycle_phase'] as String? ?? 'pre_race',
      summary = json['summary'] == null
          ? null
          : RaceSummary(json['summary'] as Map<String, dynamic>),
      circuitLayout = json['circuit_layout'] == null
          ? null
          : CircuitLayout(json['circuit_layout'] as Map<String, dynamic>),
      name = json['name'] as String,
      circuit = json['circuit'] as String,
      date = json['date'] as String,
      source = json['source'] as String,
      currentSession = json['current_session'] == null
          ? null
          : RaceSession(json['current_session'] as Map<String, dynamic>),
      nextSession = json['next_session'] == null
          ? null
          : RaceSession(json['next_session'] as Map<String, dynamic>),
      countdownTarget = json['countdown_target'] == null
          ? null
          : DateTime.parse(json['countdown_target'] as String).toLocal(),
      startsAt = json['starts_at'] == null
          ? null
          : DateTime.parse(json['starts_at'] as String).toLocal(),
      sessions = (json['sessions'] as List)
          .map((s) => RaceSession(s as Map<String, dynamic>))
          .toList();
}

class RaceFeed {
  final List<Race> races;
  final bool stale;
  final bool summariesStale;
  final DateTime updatedAt;
  RaceFeed.staleCopy(RaceFeed feed)
    : races = feed.races,
      updatedAt = feed.updatedAt,
      summariesStale = feed.summariesStale,
      stale = true;
  RaceFeed(Map<String, dynamic> json, {bool next = false})
    : races = next
          ? [
              if (json['race'] != null)
                Race(json['race'] as Map<String, dynamic>),
            ]
          : (json['races'] as List)
                .map((r) => Race(r as Map<String, dynamic>))
                .toList(),
      stale = json['stale'] as bool,
      summariesStale = json['summaries_stale'] as bool? ?? false,
      updatedAt = DateTime.parse(json['updated_at'] as String).toLocal();
}

class RaceRepository {
  final http.Client client;
  final String baseUrl;
  final SharedPreferences? preferences;
  RaceRepository({
    http.Client? client,
    this.preferences,
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
  }) : client = client ?? http.Client();

  String _cacheKey(String path) => 'api-cache:$baseUrl$path';

  Future<(dynamic, bool)> _get(String path, Duration timeout) async {
    try {
      final response = await client
          .get(Uri.parse('$baseUrl$path'))
          .timeout(timeout);
      if (response.statusCode != 200) throw Exception('Service unavailable');
      final decoded = jsonDecode(response.body);
      await preferences?.setString(_cacheKey(path), response.body);
      return (decoded, false);
    } catch (_) {
      final saved = preferences?.getString(_cacheKey(path));
      if (saved == null) rethrow;
      return (jsonDecode(saved), true);
    }
  }

  Future<List<int>> seasons() async {
    final (json, _) = await _get(
      '/api/v1/seasons',
      const Duration(seconds: 20),
    );
    return (json as List).cast<int>();
  }

  Future<RaceFeed> load({int? season, bool summaries = true}) async {
    final path = season == null
        ? '/api/v1/next-race'
        : '/api/v1/races?season=$season&summaries=$summaries';
    final (json, cached) = await _get(path, const Duration(seconds: 20));
    final body = Map<String, dynamic>.from(json as Map);
    if (cached) body['stale'] = true;
    return RaceFeed(body, next: season == null);
  }

  void dispose() => client.close();

  Future<ResultsFeed> results(String raceId, {required bool qualifying}) async {
    final kind = qualifying ? 'qualifying' : 'results';
    final path = '/api/v1/races/${Uri.encodeComponent(raceId)}/$kind';
    final (json, cached) = await _get(path, const Duration(seconds: 35));
    final body = Map<String, dynamic>.from(json as Map);
    if (cached) body['stale'] = true;
    return ResultsFeed(body);
  }

  Future<RaceStoryFeed> story(String raceId) async {
    final path = '/api/v1/races/${Uri.encodeComponent(raceId)}/story';
    final (json, cached) = await _get(path, const Duration(seconds: 35));
    final body = Map<String, dynamic>.from(json as Map);
    if (cached) body['stale'] = true;
    return RaceStoryFeed(body);
  }

  Future<SeasonRosterFeed> roster(int season) async {
    final path = '/api/v1/seasons/$season/roster';
    final (json, cached) = await _get(path, const Duration(seconds: 20));
    final body = Map<String, dynamic>.from(json as Map);
    if (cached) body['stale'] = true;
    return SeasonRosterFeed(body);
  }
}

class SeasonRosterEntry {
  final String driverId, driver, teamId, team;
  SeasonRosterEntry(Map<String, dynamic> json)
    : driverId = json['driver_id'] as String,
      driver = json['driver'] as String,
      teamId = json['team_id'] as String,
      team = json['team'] as String;
}

class SeasonRosterFeed {
  final List<SeasonRosterEntry> entries;
  final bool stale;
  SeasonRosterFeed(Map<String, dynamic> json)
    : entries = (json['entries'] as List)
          .map((entry) => SeasonRosterEntry(entry as Map<String, dynamic>))
          .toList(),
      stale = json['stale'] as bool? ?? false;
}

class ResultEntry {
  final String driver, team, classification;
  final String? internalId, driverId, teamId, time, status, q1, q2, q3;
  final String resultStatus;
  final int? grid, lapsCompleted, fastestLapNumber;
  final num? points;
  ResultEntry(Map<String, dynamic> json)
    : driver = json['driver'] as String,
      internalId = json['internal_id'] as String?,
      driverId = json['driver_id'] as String?,
      teamId = json['team_id'] as String?,
      team = json['team'] as String,
      classification = json['classification'] as String,
      time = json['time'] as String?,
      status = json['status'] as String?,
      q1 = json['q1'] as String?,
      q2 = json['q2'] as String?,
      q3 = json['q3'] as String?,
      resultStatus = json['result_status'] as String? ?? 'unknown',
      grid = json['grid'] as int?,
      lapsCompleted = json['laps_completed'] as int?,
      fastestLapNumber = json['fastest_lap_number'] as int?,
      points = json['points'] as num?;
}

class FastestLap {
  final String driver, time;
  final int lap;
  FastestLap(Map<String, dynamic> json)
    : driver = json['driver'] as String,
      time = json['time'] as String,
      lap = json['lap'] as int;
}

class ResultsFeed {
  final List<ResultEntry> entries;
  final FastestLap? fastestLap;
  final DateTime updatedAt;
  final bool stale;
  final String source;
  ResultsFeed(Map<String, dynamic> json)
    : entries = (json['entries'] as List)
          .map((r) => ResultEntry(r as Map<String, dynamic>))
          .toList(),
      fastestLap = json['fastest_lap'] == null
          ? null
          : FastestLap(json['fastest_lap'] as Map<String, dynamic>),
      updatedAt = DateTime.parse(json['updated_at'] as String).toLocal(),
      stale = json['stale'] as bool,
      source = json['source'] as String;
}

class RaceStoryEvent {
  final String kind, driver;
  final int? gridPosition, finishPosition, lap;
  final String? time;
  RaceStoryEvent(Map<String, dynamic> json)
    : kind = json['kind'] as String,
      driver = json['driver'] as String,
      gridPosition = json['grid_position'] as int?,
      finishPosition = json['finish_position'] as int?,
      lap = json['lap'] as int?,
      time = json['time'] as String?;
}

class RaceStoryFeed {
  final List<RaceStoryEvent> events;
  final DateTime updatedAt;
  final bool stale;
  RaceStoryFeed(Map<String, dynamic> json)
    : events = (json['events'] as List)
          .map((event) => RaceStoryEvent(event as Map<String, dynamic>))
          .toList(),
      updatedAt = DateTime.parse(json['updated_at'] as String).toLocal(),
      stale = json['stale'] as bool;
}
