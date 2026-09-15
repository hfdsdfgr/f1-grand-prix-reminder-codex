import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/language.dart';
import '../../data/race_repository.dart';
import '../../data/follow_service.dart';
import '../../data/reminder_service.dart';
import '../../shared/race_feed_view.dart';
import '../../shared/race_briefing_view.dart';
import '../../shared/follow_context.dart';
import '../home/home_page.dart';
import '../home/reminder_controls.dart';

class RaceDetailPage extends StatefulWidget {
  final Race race;
  final RaceRepository repository;
  final ReminderService? reminders;
  final Future<void> Function(bool)? syncReminders;
  final bool spoilerHidden;
  final VoidCallback? onReveal;
  final FollowService? follows;
  const RaceDetailPage({
    super.key,
    required this.race,
    required this.repository,
    this.reminders,
    this.syncReminders,
    this.spoilerHidden = false,
    this.onReveal,
    this.follows,
  });

  @override
  State<RaceDetailPage> createState() => _RaceDetailPageState();
}

class _RaceDetailPageState extends State<RaceDetailPage> {
  bool _qualifying = false;
  bool _revealed = false;
  final Map<bool, Future<ResultsFeed>> _requests = {};
  final Map<bool, ResultsFeed> _saved = {};
  Future<RaceStoryFeed>? _storyRequest;
  RaceStoryFeed? _savedStory;
  Future<StrategyFeed>? _strategyRequest;
  StrategyFeed? _savedStrategy;
  Future<ChampionshipImpactFeed>? _impactRequest;
  ChampionshipImpactFeed? _savedImpact;

  Future<ResultsFeed> _load() => _requests.putIfAbsent(
    _qualifying,
    () => widget.repository.results(widget.race.id, qualifying: _qualifying),
  );

  void _refresh() => setState(() {
    _requests.remove(_qualifying);
  });

  Future<RaceStoryFeed> _loadStory() =>
      _storyRequest ??= widget.repository.story(widget.race.id);

  void _refreshStory() => setState(() => _storyRequest = null);

  Future<StrategyFeed> _loadStrategy() =>
      _strategyRequest ??= widget.repository.strategy(widget.race.id);

  void _refreshStrategy() => setState(() => _strategyRequest = null);

  Future<ChampionshipImpactFeed> _loadImpact() =>
      _impactRequest ??= widget.repository.championshipImpact(widget.race.id);

  void _refreshImpact() => setState(() => _impactRequest = null);

  @override
  Widget build(BuildContext context) {
    final race = widget.race;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Race details'))),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, _phaseLabel(race.lifecyclePhase)),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(context, race.name),
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(tr(context, race.circuit)),
                  Text(
                    race.startsAt == null
                        ? race.date
                        : localDate(context, race.startsAt!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (race.circuitLayout case final layout?) ...[
                    const SizedBox(height: 24),
                    Semantics(
                      image: true,
                      label:
                          '${tr(context, race.circuit)} ${tr(context, 'circuit layout')}',
                      child: ExcludeSemantics(
                        child: SizedBox(
                          height: 220,
                          width: double.infinity,
                          child: SvgPicture.asset(
                            layout.assetPath,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(
                              Theme.of(context).colorScheme.onSurface,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      [
                        if (layout.turns != null)
                          '${layout.turns} ${tr(context, 'turns')}',
                        layout.license,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (race.lifecyclePhase != 'post_race') ...[
                    _WeekendSection(
                      race: race,
                      repository: widget.repository,
                      follows: widget.follows,
                    ),
                    if (race.lifecyclePhase == 'pre_race') ...[
                      const SizedBox(height: 32),
                      ReminderControls(
                        race: race,
                        service: widget.reminders,
                        stale: false,
                        syncReminders: widget.syncReminders,
                      ),
                    ],
                  ] else if (widget.spoilerHidden && !_revealed)
                    _SpoilerGate(
                      onReveal: () {
                        setState(() => _revealed = true);
                        widget.onReveal?.call();
                      },
                    )
                  else
                    _results(),
                  const SizedBox(height: 32),
                  Text(
                    tr(context, 'Source: Jolpica F1'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SelectableText(
                    race.source,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _results() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: Text(tr(context, 'Race result')),
            selected: !_qualifying,
            onSelected: (_) => setState(() => _qualifying = false),
          ),
          ChoiceChip(
            label: Text(tr(context, 'Qualifying')),
            selected: _qualifying,
            onSelected: (_) => setState(() => _qualifying = true),
          ),
        ],
      ),
      const SizedBox(height: 24),
      FutureBuilder<ResultsFeed>(
        key: ValueKey(_qualifying),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: tr(context, 'Loading results'),
              ),
            );
          }
          if (snapshot.hasData) _saved[_qualifying] = snapshot.data!;
          final feed = _saved[_qualifying];
          if (feed == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'Unable to load results. Please try again.')),
                TextButton(
                  onPressed: _refresh,
                  child: Text(tr(context, 'Retry')),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (feed.stale || snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    tr(
                      context,
                      'Showing saved results. They may have changed.',
                    ),
                  ),
                ),
              if (feed.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    tr(
                      context,
                      'Results have not been published or are unavailable for this session.',
                    ),
                  ),
                ),
              if (!_qualifying && feed.entries.isNotEmpty) ...[
                Text(
                  tr(context, 'Fastest lap'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (feed.fastestLap case final lap?) ...[
                  Text(
                    lap.time,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text('${lap.driver} · ${tr(context, 'Lap')} ${lap.lap}'),
                ] else
                  Text(tr(context, 'Not available')),
                const SizedBox(height: 24),
                const Divider(),
              ],
              for (final entry in feed.entries) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.classification}. ${entry.driver}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        tr(context, entry.team),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (widget.follows case final follows?) ...[
                        const SizedBox(height: 8),
                        _FollowActions(entry: entry, follows: follows),
                      ],
                      const SizedBox(height: 12),
                      if (_qualifying)
                        Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            Text('Q1  ${entry.q1 ?? '—'}'),
                            Text('Q2  ${entry.q2 ?? '—'}'),
                            Text('Q3  ${entry.q3 ?? '—'}'),
                          ],
                        )
                      else ...[
                        Text(
                          '${tr(context, 'Time / Gap')}: ${entry.time ?? '—'}',
                        ),
                        Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            Text(
                              '${tr(context, 'Grid')}: ${entry.grid == 0 ? tr(context, 'Pit lane / unlisted') : entry.grid?.toString() ?? '—'}',
                            ),
                            Text(
                              '${tr(context, 'Points')}: ${entry.points ?? '—'}',
                            ),
                          ],
                        ),
                        Text(
                          '${tr(context, 'Status')}: ${tr(context, entry.status ?? 'Not available')}',
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(),
              ],
              if (!_qualifying) ...[
                const SizedBox(height: 24),
                _RaceStory(
                  future: _loadStory(),
                  saved: _savedStory,
                  onSaved: (story) => _savedStory = story,
                  onRetry: _refreshStory,
                ),
                const SizedBox(height: 32),
                _RaceStrategy(
                  future: _loadStrategy(),
                  saved: _savedStrategy,
                  onSaved: (strategy) => _savedStrategy = strategy,
                  onRetry: _refreshStrategy,
                ),
                const SizedBox(height: 32),
                _ChampionshipImpact(
                  future: _loadImpact(),
                  saved: _savedImpact,
                  onSaved: (impact) => _savedImpact = impact,
                  onRetry: _refreshImpact,
                ),
                const SizedBox(height: 32),
                RaceBriefingView(
                  repository: widget.repository,
                  raceId: widget.race.id,
                ),
              ],
              Text(
                '${tr(context, 'Updated')} ${localDate(context, feed.updatedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, 'Refresh')),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _RaceStory extends StatelessWidget {
  final Future<RaceStoryFeed> future;
  final RaceStoryFeed? saved;
  final ValueChanged<RaceStoryFeed> onSaved;
  final VoidCallback onRetry;
  const _RaceStory({
    required this.future,
    required this.saved,
    required this.onSaved,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<RaceStoryFeed>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) onSaved(snapshot.data!);
      final story = snapshot.data ?? saved;
      if (snapshot.connectionState == ConnectionState.waiting &&
          story == null) {
        return Center(
          child: CircularProgressIndicator(
            semanticsLabel: tr(context, 'Loading race story'),
          ),
        );
      }
      if (story == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Unable to load race story. Please try again.')),
            TextButton(onPressed: onRetry, child: Text(tr(context, 'Retry'))),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Race story'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Key race facts'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (story.stale || snapshot.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr(context, 'Showing saved race story. It may have changed.'),
              ),
            ),
          const SizedBox(height: 12),
          if (story.events.isEmpty)
            Text(tr(context, 'Race story is not available yet.')),
          for (final event in story.events) _StoryEvent(event: event),
        ],
      );
    },
  );
}

class _StoryEvent extends StatelessWidget {
  final RaceStoryEvent event;
  const _StoryEvent({required this.event});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '${tr(context, _storyTitle(event.kind))}, ${event.driver}',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _storyIcon(event.kind),
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, _storyTitle(event.kind)),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(event.driver),
                  if (event.gridPosition != null)
                    Text(
                      '${tr(context, 'Start')} P${event.gridPosition} · ${tr(context, 'Finish')} P${event.finishPosition}',
                    ),
                  if (event.lap != null)
                    Text('${tr(context, 'Lap')} ${event.lap} · ${event.time}'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RaceStrategy extends StatelessWidget {
  final Future<StrategyFeed> future;
  final StrategyFeed? saved;
  final ValueChanged<StrategyFeed> onSaved;
  final VoidCallback onRetry;
  const _RaceStrategy({
    required this.future,
    required this.saved,
    required this.onSaved,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<StrategyFeed>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) onSaved(snapshot.data!);
      final strategy = snapshot.data ?? saved;
      if (snapshot.connectionState == ConnectionState.waiting &&
          strategy == null) {
        return Center(
          child: CircularProgressIndicator(
            semanticsLabel: tr(context, 'Loading strategy'),
          ),
        );
      }
      if (strategy == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Unable to load strategy. Please try again.')),
            TextButton(onPressed: onRetry, child: Text(tr(context, 'Retry'))),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Strategy view'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Tyre compounds and verified pit laps.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (strategy.stale || snapshot.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr(context, 'Showing saved strategy. It may have changed.'),
              ),
            ),
          const SizedBox(height: 12),
          if (strategy.drivers.isEmpty)
            Text(tr(context, 'Strategy data is not available yet.')),
          for (final driver in strategy.drivers)
            _DriverStrategy(strategy: driver),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Source: FastF1'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SelectableText(
            strategy.source,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

class _DriverStrategy extends StatelessWidget {
  final DriverStrategy strategy;
  const _DriverStrategy({required this.strategy});

  @override
  Widget build(BuildContext context) {
    final stops = strategy.stints.where((stint) => stint.pitLap != null).length;
    final detail = strategy.stints
        .map((stint) => _stintText(context, stint))
        .join(' → ');
    return Semantics(
      container: true,
      label:
          '${strategy.driver}: $detail; $stops ${tr(context, stops == 1 ? 'stop' : 'stops')}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strategy.driver,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final stint in strategy.stints)
                    Text(_stintText(context, stint)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${tr(context, 'Stops')}: $stops',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChampionshipImpact extends StatelessWidget {
  final Future<ChampionshipImpactFeed> future;
  final ChampionshipImpactFeed? saved;
  final ValueChanged<ChampionshipImpactFeed> onSaved;
  final VoidCallback onRetry;
  const _ChampionshipImpact({
    required this.future,
    required this.saved,
    required this.onSaved,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<ChampionshipImpactFeed>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) onSaved(snapshot.data!);
      final impact = snapshot.data ?? saved;
      if (snapshot.connectionState == ConnectionState.waiting &&
          impact == null) {
        return Center(
          child: CircularProgressIndicator(
            semanticsLabel: tr(context, 'Loading championship impact'),
          ),
        );
      }
      if (impact == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                context,
                'Unable to load championship impact. Please try again.',
              ),
            ),
            TextButton(onPressed: onRetry, child: Text(tr(context, 'Retry'))),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Championship impact'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              'Standings after this race, compared with the previous round.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (impact.stale || snapshot.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr(
                  context,
                  'Showing saved championship impact. It may have changed.',
                ),
              ),
            ),
          const SizedBox(height: 12),
          _ChampionshipTable(
            title: 'Drivers’ championship',
            entries: impact.drivers,
          ),
          const SizedBox(height: 20),
          _ChampionshipTable(
            title: 'Constructors’ championship',
            entries: impact.constructors,
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Source: Jolpica F1'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (impact.sources.isNotEmpty)
            SelectableText(
              impact.sources.first,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      );
    },
  );
}

class _ChampionshipTable extends StatelessWidget {
  final String title;
  final List<ChampionshipStanding> entries;
  const _ChampionshipTable({required this.title, required this.entries});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(tr(context, title), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (entries.isEmpty)
        Text(tr(context, 'Championship data is not available yet.')),
      for (final entry in entries.take(3)) _ChampionshipRow(entry: entry),
    ],
  );
}

class _ChampionshipRow extends StatelessWidget {
  final ChampionshipStanding entry;
  const _ChampionshipRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final change = [
      if (entry.previousPosition != null)
        'P${entry.previousPosition} → P${entry.position}',
      if (entry.pointsChange != null)
        '${entry.pointsChange! >= 0 ? '+' : ''}${_points(entry.pointsChange!)} ${tr(context, 'points')}',
    ].join(' · ');
    return Semantics(
      container: true,
      label:
          'P${entry.position}, ${entry.name}, ${_points(entry.points)} ${tr(context, 'points')}'
          '${change.isEmpty ? '' : ', $change'}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('P${entry.position} · ${entry.name}'),
              Text(
                '${_points(entry.points)} ${tr(context, 'points')}'
                '${change.isEmpty ? '' : ' · $change'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _points(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

String _stintText(BuildContext context, StrategyStint stint) => [
  tr(context, stint.compound),
  '${tr(context, 'Lap')} ${stint.startLap}–${stint.endLap}',
  if (stint.tyreAgeAtStart != null)
    '${tr(context, 'Tyre age')} ${stint.tyreAgeAtStart}',
  if (stint.pitLap != null)
    '${tr(context, 'Pit')} ${tr(context, 'Lap')} ${stint.pitLap}',
].join(' · ');

String _storyTitle(String kind) => switch (kind) {
  'finish' => 'Winner',
  'gain' => 'Biggest gain',
  'loss' => 'Biggest loss',
  _ => 'Fastest lap',
};

IconData _storyIcon(String kind) => switch (kind) {
  'finish' => Icons.emoji_events_outlined,
  'gain' => Icons.trending_up,
  'loss' => Icons.trending_down,
  _ => Icons.speed_outlined,
};

class _FollowActions extends StatelessWidget {
  final ResultEntry entry;
  final FollowService follows;
  const _FollowActions({required this.entry, required this.follows});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: follows,
    builder: (context, _) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (entry.driverId case final id?)
          _FollowButton(
            label: 'driver',
            followed: follows.followsDriver(id),
            onPressed: () => follows.toggleDriver(id, entry.driver),
          ),
        if (entry.teamId case final id?)
          _FollowButton(
            label: 'team',
            followed: follows.followsTeam(id),
            onPressed: () => follows.toggleTeam(id, entry.team),
          ),
      ],
    ),
  );
}

class _FollowButton extends StatelessWidget {
  final String label;
  final bool followed;
  final Future<void> Function() onPressed;
  const _FollowButton({
    required this.label,
    required this.followed,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(followed ? Icons.star : Icons.star_border),
    label: Text(tr(context, followed ? 'Following $label' : 'Follow $label')),
  );
}

class _SpoilerGate extends StatelessWidget {
  final VoidCallback? onReveal;
  const _SpoilerGate({this.onReveal});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tr(context, 'Race completed'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(tr(context, 'Results hidden')),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: onReveal,
        child: Text(tr(context, 'Reveal this session')),
      ),
    ],
  );
}

class _WeekendSection extends StatelessWidget {
  final Race race;
  final RaceRepository repository;
  final FollowService? follows;
  const _WeekendSection({
    required this.race,
    required this.repository,
    this.follows,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tr(context, 'Weekend hub'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 20),
      if (race.currentSession case final current?) ...[
        Text(
          tr(context, 'Current session'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr(context, current.kind),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
      ] else if (race.nextSession case final next?) ...[
        Text(
          tr(context, 'Next session'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr(context, next.kind),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (next.startsAt != null) ...[
          const SizedBox(height: 4),
          Text(localDate(context, next.startsAt!)),
          const SizedBox(height: 16),
          Countdown(
            startsAt: next.startsAt!,
            label: tr(context, 'Next session starts in'),
          ),
        ],
        const SizedBox(height: 24),
      ],
      FollowContext(
        repository: repository,
        season: race.season,
        follows: follows,
      ),
      const Divider(),
      const SizedBox(height: 24),
      Text(
        tr(context, 'Weekend schedule'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      for (final session in race.sessions) _SessionRow(session: session),
    ],
  );
}

class _SessionRow extends StatelessWidget {
  final RaceSession session;
  const _SessionRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final status = tr(context, sessionStatusLabel(session.status));
    return Semantics(
      container: true,
      label: '${tr(context, session.kind)}, $status',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 12),
                child: Icon(
                  _statusIcon(session.status),
                  size: 18,
                  color: session.status == 'started'
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, session.kind),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(status, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  session.startsAt == null
                      ? tr(context, 'Not available')
                      : localDate(context, session.startsAt!),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _statusIcon(String status) => switch (status) {
  'started' => Icons.radio_button_checked,
  'completed' => Icons.check_circle_outline,
  'delayed' || 'rescheduled' => Icons.schedule,
  'cancelled' => Icons.cancel_outlined,
  _ => Icons.circle_outlined,
};

String _phaseLabel(String phase) => switch (phase) {
  'race_weekend' => 'Race weekend',
  'post_race' => 'Post-race',
  _ => 'Pre-race',
};
