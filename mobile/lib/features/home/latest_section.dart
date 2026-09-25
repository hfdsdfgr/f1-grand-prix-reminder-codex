import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../data/race_repository.dart';
import '../../data/follow_service.dart';
import '../../shared/editorial.dart';
import '../../shared/presentation.dart';
import '../briefing/briefing_page.dart';
import '../evolution/evolution_page.dart';

class LatestSection extends StatefulWidget {
  const LatestSection({
    super.key,
    required this.repository,
    required this.season,
    required this.spoilerFree,
    required this.revealedSessions,
    this.onRevealSession,
    this.onOpenBriefing,
    this.follows,
  });
  final RaceRepository repository;
  final int season;
  final bool spoilerFree;
  final Set<String> revealedSessions;
  final ValueChanged<String>? onRevealSession;
  final ValueChanged<String?>? onOpenBriefing;
  final FollowService? follows;
  @override
  State<LatestSection> createState() => _LatestState();
}

class _LatestState extends State<LatestSection> {
  late Future<RaceFeed> _races = _load();
  String? _latestId;
  Future<RaceFeed> _load() async {
    final current = await widget.repository.load(
      season: widget.season,
      summaries: false,
    );
    if (current.races.any((r) => r.lifecyclePhase == 'post_race') ||
        widget.season <= 1950) {
      return current;
    }
    try {
      final previous = await widget.repository.load(
        season: widget.season - 1,
        summaries: false,
      );
      return previous.races.any((r) => r.lifecyclePhase == 'post_race')
          ? previous
          : current;
    } catch (_) {
      return current;
    }
  }

  @override
  void didUpdateWidget(covariant LatestSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.season != widget.season) _races = _load();
  }

  void _briefing(String? id) {
    if (widget.onOpenBriefing != null) {
      widget.onOpenBriefing!(id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: SingleChildScrollView(
            padding: RaceSpace.page,
            child: BriefingPage(
              repository: widget.repository,
              initialRaceId: id,
              spoilerFree: widget.spoilerFree,
              revealedSessions: widget.revealedSessions,
              onRevealSession: widget.onRevealSession,
              follows: widget.follows,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(child: EditorialLabel('Latest', accent: true)),
          TextButton(
            onPressed: () => _briefing(_latestId),
            child: Text(tr(context, 'View all')),
          ),
        ],
      ),
      const Divider(),
      FutureBuilder<RaceFeed>(
        future: _races,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ContentState(
              tr(context, 'Unable to load races'),
              onRetry: () => setState(() => _races = _load()),
            );
          }
          if (!snapshot.hasData) {
            return ContentState(tr(context, 'Loading races'), loading: true);
          }
          final completed =
              snapshot.data!.races
                  .where((r) => r.lifecyclePhase == 'post_race')
                  .toList()
                ..sort((a, b) => a.date.compareTo(b.date));
          if (completed.isEmpty) {
            return ContentState(
              tr(context, 'No completed race is available for briefing.'),
            );
          }
          final race = completed.last;
          _latestId = race.id;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              EditorialLabel(tr(context, race.name)),
              if (snapshot.data!.stale)
                ContentState(
                  tr(
                    context,
                    'Showing saved schedule. Times may have changed.',
                  ),
                ),
              _Availability(
                key: ValueKey('${race.id}-${Localizations.localeOf(context)}'),
                repository: widget.repository,
                race: race,
                onBriefing: _briefing,
                follows: widget.follows,
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _Availability extends StatefulWidget {
  const _Availability({
    super.key,
    required this.repository,
    required this.race,
    required this.onBriefing,
    this.follows,
  });
  final RaceRepository repository;
  final Race race;
  final ValueChanged<String?> onBriefing;
  final FollowService? follows;
  @override
  State<_Availability> createState() => _AvailabilityState();
}

class _AvailabilityState extends State<_Availability> {
  late Future<RaceBriefingFeed> _briefing = widget.repository.briefing(
    widget.race.id,
  );
  late Future<EvolutionFeed> _evolution = widget.repository.evolutionRace(
    widget.race.id,
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      FutureBuilder<RaceBriefingFeed>(
        future: _briefing,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ContentState(
              tr(context, 'Unable to load race briefing. Please try again.'),
              onRetry: () => setState(
                () => _briefing = widget.repository.briefing(widget.race.id),
              ),
            );
          }
          if (!snapshot.hasData) {
            return ContentState(
              tr(context, 'Loading race briefing'),
              loading: true,
            );
          }
          return EditorialRow(
            title: snapshot.data!.insights.isEmpty
                ? 'No verified briefing is available for this race.'
                : 'Briefing available',
            subtitle: snapshot.data!.stale
                ? tr(context, 'Saved content')
                : null,
            onTap: () => widget.onBriefing(widget.race.id),
          );
        },
      ),
      FutureBuilder<EvolutionFeed>(
        future: _evolution,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ContentState(
              tr(context, 'Unable to load upgrades. Please retry.'),
              onRetry: () => setState(
                () => _evolution = widget.repository.evolutionRace(
                  widget.race.id,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return ContentState(tr(context, 'Loading upgrades'), loading: true);
          }
          return EditorialRow(
            title:
                '${snapshot.data!.upgrades.length} ${tr(context, 'documented updates')}',
            subtitle: snapshot.data!.stale
                ? tr(context, 'Saved content')
                : null,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(),
                  body: SingleChildScrollView(
                    padding: RaceSpace.page,
                    child: EvolutionPage(
                      repository: widget.repository,
                      raceId: widget.race.id,
                      follows: widget.follows,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}
