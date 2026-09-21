import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_config.dart';

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
    this.baseUrl = ApiConfig.baseUrl,
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

  Future<StrategyFeed> strategy(String raceId) async {
    final path = '/api/v1/races/${Uri.encodeComponent(raceId)}/strategy';
    final (json, cached) = await _get(path, const Duration(seconds: 45));
    final body = Map<String, dynamic>.from(json as Map);
    if (cached) body['stale'] = true;
    return StrategyFeed(body);
  }

  Future<ChampionshipImpactFeed> championshipImpact(String raceId) async {
    final path =
        '/api/v1/races/${Uri.encodeComponent(raceId)}/championship-impact';
    final (json, cached) = await _get(path, const Duration(seconds: 20));
    final body = Map<String, dynamic>.from(json as Map);
    if (cached) body['stale'] = true;
    return ChampionshipImpactFeed(body);
  }

  Future<RaceBriefingFeed> briefing(String raceId) async {
    final path = '/api/v1/races/${Uri.encodeComponent(raceId)}/briefing';
    final (json, cached) = await _get(path, const Duration(seconds: 20));
    final body = Map<String, dynamic>.from(json as Map);
    if (cached) body['stale'] = true;
    return RaceBriefingFeed(body);
  }

  Future<SeasonRosterFeed> roster(int season) async {
    final path = '/api/v1/seasons/$season/roster';
    final (json, cached) = await _get(path, const Duration(seconds: 20));
    final body = Map<String, dynamic>.from(json as Map);
    if (cached) body['stale'] = true;
    return SeasonRosterFeed(body);
  }

  Future<EvolutionFeed> evolution(int season) async {
    final (json, cached) = await _get(
      '/api/v1/evolution?season=$season',
      const Duration(seconds: 20),
    );
    return EvolutionFeed(
      Map<String, dynamic>.from(json as Map),
      cached: cached,
    );
  }
}

class UpgradeEntry {
  final String id, teamId, team, component, title, status, confidence;
  final String? raceId, race, componentId, change, goal, expectedEffect;
  final int? round;
  final List<BriefingSource> sources;
  UpgradeEntry(Map<String, dynamic> json)
    : id = json['id'] as String,
      teamId = json['team_id'] as String,
      team = json['team'] as String,
      component = json['component'] as String,
      title = json['title'] as String,
      status = json['status'] as String,
      confidence = json['confidence'] as String,
      raceId = json['race_id'] as String?,
      race = json['race'] as String?,
      round = json['round'] as int?,
      componentId = json['component_id'] as String?,
      change = json['change'] as String?,
      goal = json['goal'] as String?,
      expectedEffect = json['expected_effect'] as String?,
      sources = (json['sources'] as List)
          .map((s) => BriefingSource(s as Map<String, dynamic>))
          .toList();
}

class EvolutionTimelineEvent {
  final String raceId, race;
  final int round;
  final List<String> upgradeIds;
  EvolutionTimelineEvent(Map<String, dynamic> json)
    : raceId = json['race_id'] as String,
      race = json['race'] as String,
      round = json['round'] as int,
      upgradeIds = List<String>.from(json['upgrade_ids'] as List);
}

class EvolutionFeed {
  final List<UpgradeEntry> upgrades;
  final List<EvolutionTimelineEvent> timeline;
  final bool stale;
  EvolutionFeed(Map<String, dynamic> json, {bool cached = false})
    : upgrades = (json['upgrades'] as List)
          .map((u) => UpgradeEntry(u as Map<String, dynamic>))
          .toList(),
      timeline = (json['timeline'] as List<dynamic>? ?? const [])
          .map((event) => EvolutionTimelineEvent(event as Map<String, dynamic>))
          .toList(),
      stale = cached || (json['stale'] as bool? ?? false);
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

class StrategyStint {
  final String compound;
  final int startLap, endLap;
  final int? tyreAgeAtStart, pitLap;
  StrategyStint(Map<String, dynamic> json)
    : compound = json['compound'] as String,
      startLap = json['start_lap'] as int,
      endLap = json['end_lap'] as int,
      tyreAgeAtStart = json['tyre_age_at_start'] as int?,
      pitLap = json['pit_lap'] as int?;
}

class DriverStrategy {
  final String driver;
  final List<StrategyStint> stints;
  DriverStrategy(Map<String, dynamic> json)
    : driver = json['driver'] as String,
      stints = (json['stints'] as List)
          .map((stint) => StrategyStint(stint as Map<String, dynamic>))
          .toList();
}

class StrategyFeed {
  final List<DriverStrategy> drivers;
  final DateTime updatedAt;
  final String source;
  final bool stale;
  StrategyFeed(Map<String, dynamic> json)
    : drivers = (json['drivers'] as List)
          .map((driver) => DriverStrategy(driver as Map<String, dynamic>))
          .toList(),
      updatedAt = DateTime.parse(json['updated_at'] as String).toLocal(),
      source = json['source'] as String,
      stale = json['stale'] as bool;
}

class ChampionshipStanding {
  final String name;
  final int position;
  final double points;
  final int? previousPosition;
  final double? pointsChange;
  ChampionshipStanding(Map<String, dynamic> json)
    : name = json['name'] as String,
      position = json['position'] as int,
      points = (json['points'] as num).toDouble(),
      previousPosition = json['previous_position'] as int?,
      pointsChange = (json['points_change'] as num?)?.toDouble();
}

class ChampionshipImpactFeed {
  final List<ChampionshipStanding> drivers, constructors;
  final List<String> sources;
  final DateTime updatedAt;
  final bool stale;
  ChampionshipImpactFeed(Map<String, dynamic> json)
    : drivers = (json['drivers'] as List)
          .map((entry) => ChampionshipStanding(entry as Map<String, dynamic>))
          .toList(),
      constructors = (json['constructors'] as List)
          .map((entry) => ChampionshipStanding(entry as Map<String, dynamic>))
          .toList(),
      sources = (json['sources'] as List).cast<String>(),
      updatedAt = DateTime.parse(json['updated_at'] as String).toLocal(),
      stale = json['stale'] as bool;
}

class BriefingInsight {
  final String topic, detail;
  BriefingInsight(Map<String, dynamic> json)
    : topic = json['topic'] as String,
      detail = json['detail'] as String;
}

class BriefingSource {
  final String url;
  final String? provider;
  final DateTime? publishedAt;
  BriefingSource(Map<String, dynamic> json)
    : url = json['url'] as String,
      provider = json['provider'] as String?,
      publishedAt = json['published_at'] == null
          ? null
          : DateTime.parse(json['published_at'] as String).toLocal();
}

class RaceBriefingFeed {
  final String raceId;
  final List<BriefingInsight> insights;
  final List<BriefingSource> sources;
  final DateTime updatedAt;
  final bool stale;
  RaceBriefingFeed(Map<String, dynamic> json)
    : raceId = json['race_id'] as String,
      insights = (json['insights'] as List)
          .map((item) => BriefingInsight(item as Map<String, dynamic>))
          .toList(),
      sources = (json['sources'] as List)
          .map((item) => BriefingSource(item as Map<String, dynamic>))
          .toList(),
      updatedAt = DateTime.parse(json['updated_at'] as String).toLocal(),
      stale = json['stale'] as bool? ?? false;
}
