import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/spoilers.dart';
import '../../data/race_repository.dart';
import '../../data/follow_service.dart';
import '../../data/reminder_service.dart';
import '../../shared/race_feed_view.dart';
import 'race_detail_page.dart';

class RacesPage extends StatefulWidget {
  final RaceRepository repository;
  final ReminderService? reminders;
  final Future<void> Function(bool)? syncReminders;
  final bool spoilerFree;
  final Set<String> revealedSessions;
  final ValueChanged<String>? onRevealSession;
  final FollowService? follows;
  const RacesPage({
    super.key,
    required this.repository,
    this.reminders,
    this.syncReminders,
    this.spoilerFree = false,
    this.revealedSessions = const {},
    this.onRevealSession,
    this.follows,
  });
  @override
  State<RacesPage> createState() => _RacesPageState();
}

class _RacesPageState extends State<RacesPage> {
  int _season = DateTime.now().year;
  late final Future<List<int>> _seasons = widget.repository.seasons();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tr(context, 'Races'),
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 24),
      FutureBuilder<List<int>>(
        future: _seasons,
        builder: (context, snapshot) => DropdownButtonFormField<int>(
          initialValue: _season,
          decoration: InputDecoration(labelText: tr(context, 'Season')),
          items: [
            for (final year in snapshot.data ?? [_season])
              DropdownMenuItem(value: year, child: Text('$year')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _season = value);
          },
        ),
      ),
      const SizedBox(height: 32),
      RaceFeedView(
        repository: widget.repository,
        season: _season,
        builder: (feed) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (feed.summariesStale)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  tr(
                    context,
                    'Showing saved race summaries. Results may have changed.',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            for (final race in feed.races) ...[
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RaceDetailPage(
                      race: race,
                      repository: widget.repository,
                      reminders: widget.reminders,
                      syncReminders: widget.syncReminders,
                      spoilerHidden: _hidden(race),
                      onReveal: () => widget.onRevealSession?.call(
                        spoilerSessionKey(race.id),
                      ),
                      follows: widget.follows,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, race.name),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          context,
                          race.lifecyclePhase == 'race_weekend'
                              ? 'Race weekend'
                              : race.status == 'completed'
                              ? 'Race completed'
                              : 'Pre-race',
                        ),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: race.lifecyclePhase == 'race_weekend'
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        tr(context, race.circuit),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        race.startsAt == null
                            ? '${race.date} · ${tr(context, 'Time to be confirmed')}'
                            : localDate(context, race.startsAt!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (race.status == 'completed' && _hidden(race)) ...[
                        const SizedBox(height: 12),
                        Text(tr(context, 'Race completed')),
                        Text(
                          tr(context, 'Results hidden'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        TextButton(
                          onPressed: () => widget.onRevealSession?.call(
                            spoilerSessionKey(race.id),
                          ),
                          child: Text(tr(context, 'Reveal results')),
                        ),
                      ] else if (race.status == 'completed') ...[
                        const SizedBox(height: 12),
                        Text(
                          '${tr(context, 'Winner')}: ${race.summary?.winner ?? tr(context, 'Not available')}',
                        ),
                        if (race.summary?.winnerTeam case final team?)
                          Text(
                            tr(context, team),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '${tr(context, 'Fastest lap')}: ${race.summary?.fastestLapDriver ?? tr(context, 'Not available')}',
                        ),
                        if (race.summary?.fastestLapTime case final time?)
                          Text(
                            '$time${race.summary?.fastestLapNumber == null ? '' : ' · ${tr(context, 'Lap')} ${race.summary!.fastestLapNumber}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        tr(context, 'View details'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
            ],
          ],
        ),
      ),
    ],
  );

  bool _hidden(Race race) => hidesRaceResult(
    enabled: widget.spoilerFree,
    phase: race.lifecyclePhase,
    raceId: race.id,
    revealedSessions: widget.revealedSessions,
  );
}
