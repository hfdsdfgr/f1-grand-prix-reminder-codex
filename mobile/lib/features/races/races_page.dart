import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/spoilers.dart';
import '../../data/race_repository.dart';
import '../../data/follow_service.dart';
import '../../data/reminder_service.dart';
import '../../shared/race_feed_view.dart';
import '../../shared/editorial.dart';
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
  bool _completedFirst = false;
  late final Future<List<int>> _seasons = widget.repository.seasons();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const EditorialHeader(title: 'Calendar'),
      const SizedBox(height: 16),
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
      CheckboxListTile(
        key: const ValueKey('completed-first'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          tr(context, 'Completed races first'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        value: _completedFirst,
        onChanged: (value) => setState(() => _completedFirst = value!),
      ),
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
            for (final race in _ordered(feed.races)) ...[
              Semantics(
                button: true,
                hint: tr(context, 'View details'),
                child: InkWell(
                  key: ValueKey('calendar-${race.id}'),
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 36,
                          child: Semantics(
                            label:
                                '${tr(context, 'Round')} ${race.round ?? ''}',
                            child: Text(
                              race.round?.toString().padLeft(2, '0') ?? '—',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(context, race.name),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Tooltip(
                                message: tr(context, race.circuit),
                                child: Text(
                                  tr(context, race.circuit),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                MaterialLocalizations.of(
                                  context,
                                ).formatMediumDate(
                                  race.startsAt ?? DateTime.parse(race.date),
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _stateLabel(context, race),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: _completed(race)
                                          ? Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                          : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    ],
  );

  bool _completed(Race race) =>
      race.status == 'completed' || race.lifecyclePhase == 'post_race';

  List<Race> _ordered(List<Race> races) => [...races]
    ..sort((a, b) {
      final aFirst = _completed(a) == _completedFirst;
      final bFirst = _completed(b) == _completedFirst;
      if (aFirst != bFirst) return aFirst ? -1 : 1;
      final order = a.round != null && b.round != null
          ? a.round!.compareTo(b.round!)
          : a.date.compareTo(b.date);
      return order != 0 ? order : a.id.compareTo(b.id);
    });

  String _stateLabel(BuildContext context, Race race) {
    if (_completed(race)) {
      if (_hidden(race)) return tr(context, 'Results hidden');
      final winner = race.summary?.winner;
      return winner == null
          ? tr(context, 'Race completed')
          : '${tr(context, 'Winner')}: $winner';
    }
    return tr(
      context,
      race.lifecyclePhase == 'race_weekend' ? 'Race weekend' : 'Upcoming',
    );
  }

  bool _hidden(Race race) => hidesRaceResult(
    enabled: widget.spoilerFree,
    phase: race.lifecyclePhase,
    raceId: race.id,
    revealedSessions: widget.revealedSessions,
  );
}
