import 'package:flutter/material.dart';

import '../../shared/presentation.dart';
import '../../shared/editorial.dart';
import '../../shared/team_identity.dart';
import 'component_explorer.dart';

import '../../core/language.dart';
import '../../data/follow_service.dart';
import '../../data/race_repository.dart';
import 'car_model.dart';
import 'car_viewer.dart';
import 'compare_panel.dart';

class EvolutionPage extends StatefulWidget {
  final RaceRepository repository;
  final bool enableGltf;
  final String? raceId;
  final FollowService? follows;
  const EvolutionPage({
    super.key,
    required this.repository,
    this.enableGltf = true,
    this.raceId,
    this.follows,
  });

  @override
  State<EvolutionPage> createState() => _EvolutionPageState();
}

class _EvolutionPageState extends State<EvolutionPage> {
  int _season = DateTime.now().year;
  String? _team, _race;
  String? _selectedUpgrade, _highlightedComponent;
  bool _compareSpecification = false;
  bool _allTeams = true;
  bool _ghostCompare = false;
  String? _language;
  EvolutionFeed? _loadedFeed;
  late Future<EvolutionFeed> _request = _fetch();

  Future<EvolutionFeed> _fetch() => widget.raceId == null
      ? widget.repository.evolution(_season)
      : widget.repository.evolutionRace(widget.raceId!);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).toLanguageTag();
    if (_language != null && _language != language) {
      _request = _fetch();
    }
    _language = language;
  }

  void _load() => setState(() {
    _request = _fetch();
  });

  void _selectUpgrade(UpgradeEntry entry) => setState(() {
    _team = _evolutionTeamKey(entry);
    _selectedUpgrade = entry.id;
    _highlightedComponent = entry.componentId;
  });

  void _clearSelection() {
    _selectedUpgrade = null;
    _highlightedComponent = null;
  }

  void _clearCompare() {
    _compareSpecification = false;
    _ghostCompare = false;
  }

  void _openComponent(String componentId) {
    final race = widget.raceId ?? _race;
    final entries =
        _loadedFeed?.upgrades
            .where(
              (entry) =>
                  entry.componentId == componentId &&
                  (_team == null || _evolutionTeamKey(entry) == _team) &&
                  (race == null || entry.raceId == race),
            )
            .toList() ??
        <UpgradeEntry>[];
    setState(() {
      _highlightedComponent = componentId;
      _selectedUpgrade = entries.firstOrNull?.id;
    });
    if (entries.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ComponentExplorer(
            entries: entries,
            initialId: entries.first.id,
            enableGltf: widget.enableGltf,
            stale: _loadedFeed?.stale ?? false,
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorialHeader(title: 'Upgrade timeline'),
              Text(componentId),
              ContentState(tr(context, 'No recorded upgrade')),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FutureBuilder<EvolutionFeed>(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ContentState(tr(context, 'Loading upgrades'), loading: true);
          }
          if (!snapshot.hasData || snapshot.hasError) {
            return ContentState(
              tr(context, 'Unable to load upgrades. Please retry.'),
              onRetry: _load,
            );
          }
          final feed = snapshot.data!;
          if (!identical(_loadedFeed, feed)) {
            final firstLoad = _loadedFeed == null;
            _loadedFeed = feed;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (firstLoad && feed.upgrades.isNotEmpty) {
                final latest = [...feed.upgrades]
                  ..sort((a, b) => (b.round ?? 0).compareTo(a.round ?? 0));
                if (widget.raceId == null) _race = latest.first.raceId;
                _selectUpgrade(latest.first);
              }
            });
          }
          return AnimatedBuilder(
            animation: widget.follows ?? _neverNotify,
            builder: (context, _) => _content(context, feed),
          );
        },
      ),
    ],
  );

  Widget _content(BuildContext context, EvolutionFeed feed) {
    final extraTeams = {
      for (final entry in feed.upgrades)
        if (carTeamKey(entry.teamId, entry.team) == 'neutral')
          _evolutionTeamKey(entry): entry.team,
    };
    final validTeamIds = {
      ...carTeams.map((item) => item.id),
      ...extraTeams.keys,
    };
    final team = validTeamIds.contains(_team)
        ? _team!
        : feed.upgrades.isNotEmpty
        ? _evolutionTeamKey(feed.upgrades.first)
        : carTeams.first.id;
    if (_team != team) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _team != team) setState(() => _team = team);
      });
    }
    final teamEntries = feed.upgrades
        .where((u) => _allTeams || _evolutionTeamKey(u) == team)
        .toList();
    teamEntries.sort((a, b) => _teamScore(b).compareTo(_teamScore(a)));
    final races = {
      for (final u in teamEntries)
        if (u.raceId != null) u.raceId!: u.race!,
    };
    final validRaceIds = {
      ...races.keys,
      ...feed.timeline.map((event) => event.raceId),
    };
    final race = widget.raceId ?? (validRaceIds.contains(_race) ? _race : null);
    final entries = teamEntries
        .where((u) => race == null || u.raceId == race)
        .toList();
    final currentCar = feed.cars
        .where((car) => carTeamKey(car.teamId, car.team) == team)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorialHeader(
          title: 'Evolution',
          eyebrow: race == null
              ? '${tr(context, 'Season')} $_season'
              : tr(
                  context,
                  feed.timeline
                          .where((event) => event.raceId == race)
                          .firstOrNull
                          ?.race ??
                      entries.firstOrNull?.race ??
                      race,
                ),
          subtitle: race == null
              ? 'Follow what changes on the cars.'
              : 'How the car changed this weekend.',
          trailing: EditorialShare(
            title: tr(context, 'Evolution'),
            sources: entries
                .expand((e) => e.sources.map((s) => s.url))
                .toSet()
                .toList(),
          ),
        ),
        if (feed.stale)
          ContentState(
            tr(context, 'Showing saved upgrades. They may have changed.'),
          ),
        ...[
          DropdownButtonFormField<String>(
            key: ValueKey('team-$_season-$team-$_allTeams'),
            initialValue: _allTeams ? '*' : team,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(context, 'Team')),
            items: [
              DropdownMenuItem(
                value: '*',
                child: Text(tr(context, 'All teams')),
              ),
              for (final item in carTeams)
                DropdownMenuItem(
                  value: item.id,
                  child: TeamIdentity.label(
                    teamId: item.id,
                    teamName: item.name,
                  ),
                ),
              for (final item in extraTeams.entries)
                DropdownMenuItem(
                  value: item.key,
                  child: TeamIdentity.label(
                    teamId: item.key,
                    teamName: item.value,
                  ),
                ),
            ],
            onChanged: (value) => setState(() {
              _allTeams = value == '*';
              if (!_allTeams) _team = value;
              _race = null;
              _clearSelection();
              _clearCompare();
            }),
          ),
          const SizedBox(height: 16),
          EditorialLabel(
            '${entries.length} ${tr(context, 'documented updates')}',
          ),
          CarViewer(
            editorial: true,
            enableGltf: widget.enableGltf,
            highlightedComponentId: _highlightedComponent,
            highlightedTeamId: team,
            onComponentSelected: _openComponent,
            showTeamSelector: false,
            currentCarName: currentCar?.carName,
            currentCarSeason: currentCar?.season,
            currentCarSourceUrl: currentCar?.sourceUrl,
            ghostCompare: _ghostCompare,
            ghostComponentIds: _ghostComponents,
          ),
          const SizedBox(height: 32),
        ],
        for (var i = 0; i < entries.length; i++)
          EditorialRow(
            key: ValueKey(entries[i].id),
            selected: entries[i].id == _selectedUpgrade,
            number: i + 1,
            title: entries[i].component,
            subtitle:
                '${tr(context, entries[i].team)} · ${tr(context, entries[i].status)}',
            detail: entries[i].change ?? entries[i].title,
            thumbnail: carComponentIds.contains(entries[i].componentId)
                ? ComponentThumbnail(
                    componentId: entries[i].componentId!,
                    teamId: entries[i].teamId,
                  )
                : null,
            onTap: () {
              _selectUpgrade(entries[i]);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComponentExplorer(
                    entries: entries,
                    initialId: entries[i].id,
                    enableGltf: widget.enableGltf,
                    stale: feed.stale,
                  ),
                ),
              );
            },
          ),
        if (entries.isEmpty)
          ContentState(tr(context, 'No recorded upgrades for this selection.')),
        if (widget.raceId == null) ...[
          Row(
            children: [
              IconButton(
                tooltip: tr(context, 'Previous season'),
                onPressed: _season > 1950
                    ? () {
                        _season--;
                        _loadedFeed = null;
                        _team = null;
                        _race = null;
                        _clearSelection();
                        _clearCompare();
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${tr(context, 'Season')} $_season',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: tr(context, 'Next season'),
                onPressed: _season < DateTime.now().year
                    ? () {
                        _season++;
                        _loadedFeed = null;
                        _team = null;
                        _race = null;
                        _clearSelection();
                        _clearCompare();
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (feed.timeline.isNotEmpty || teamEntries.isNotEmpty) ...[
          SectionHeading(tr(context, 'Season Evolution')),
          const SizedBox(height: 16),
          if (widget.raceId == null && feed.timeline.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(tr(context, 'All races')),
                  selected: race == null,
                  onSelected: (_) => setState(() {
                    _race = null;
                    _clearSelection();
                    _clearCompare();
                  }),
                ),
                for (final event in feed.timeline)
                  Builder(
                    builder: (context) {
                      final upgrades = teamEntries
                          .where((u) => u.raceId == event.raceId)
                          .toList();
                      final hasUpgrade = upgrades.isNotEmpty;
                      return Semantics(
                        label:
                            '${event.race}. ${tr(context, hasUpgrade ? 'Upgrade' : 'No recorded upgrade')}',
                        selected: race == event.raceId,
                        child: ChoiceChip(
                          key: ValueKey('evolution-${event.raceId}'),
                          avatar: Icon(
                            hasUpgrade ? Icons.circle : Icons.circle_outlined,
                            size: 10,
                          ),
                          label: Text(
                            '${event.round} ${tr(context, event.race)}',
                          ),
                          selected: race == event.raceId,
                          onSelected: (_) {
                            setState(() {
                              _race = event.raceId;
                              _clearCompare();
                            });
                            if (hasUpgrade) {
                              _selectUpgrade(upgrades.first);
                            } else {
                              setState(_clearSelection);
                            }
                          },
                        ),
                      );
                    },
                  ),
              ],
            )
          else if (widget.raceId == null)
            DropdownButtonFormField<String>(
              key: ValueKey('race-$_season-$team-$race'),
              initialValue: race,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(context, 'Grand Prix')),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(tr(context, 'All races')),
                ),
                for (final r in races.entries)
                  DropdownMenuItem(
                    value: r.key,
                    child: Text(tr(context, r.value)),
                  ),
              ],
              onChanged: (value) => setState(() {
                _race = value;
                _clearCompare();
                _clearSelection();
              }),
            ),
          const SizedBox(height: 24),
          if (race != null && entries.isNotEmpty) ...[
            FilterChip(
              key: const ValueKey('specification-compare'),
              avatar: const Icon(Icons.compare_arrows, size: 18),
              label: Text(tr(context, 'Specification Compare')),
              selected: _compareSpecification,
              onSelected: (value) =>
                  setState(() => _compareSpecification = value),
            ),
            if (_compareSpecification) ...[
              const SizedBox(height: 16),
              EvolutionComparePanel(
                previous: tr(
                  context,
                  _previousRace(feed, race)?.race ?? 'Launch specification',
                ),
                current: tr(context, entries.first.race ?? race),
                changes: [
                  for (final entry in entries)
                    CompareChange(
                      componentId: entry.componentId ?? '',
                      component: tr(context, entry.component),
                      change: entry.change ?? tr(context, 'Not available'),
                      goal: entry.goal,
                      expectedEffect: entry.expectedEffect,
                      status: entry.status,
                    ),
                ],
                ghostAvailable: false,
                ghostEnabled: _ghostCompare,
                onGhostChanged: (value) =>
                    setState(() => _ghostCompare = value),
                onComponentSelected: (componentId) {
                  final match = entries.where(
                    (entry) => entry.componentId == componentId,
                  );
                  if (match.isNotEmpty) _selectUpgrade(match.first);
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
        TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(tr(context, 'Refresh')),
        ),
      ],
    );
  }

  int _teamScore(UpgradeEntry entry) =>
      widget.follows?.followsTeam(entry.teamId) == true ? 1 : 0;

  EvolutionTimelineEvent? _previousRace(EvolutionFeed feed, String raceId) {
    final current = feed.timeline
        .where((event) => event.raceId == raceId)
        .firstOrNull;
    if (current == null) return null;
    return feed.timeline
        .where((event) => event.round < current.round)
        .lastOrNull;
  }

  Set<String> get _ghostComponents {
    if (!_ghostCompare || _loadedFeed == null) return const {};
    final race = widget.raceId ?? _race;
    if (race == null) return const {};
    return _loadedFeed!.upgrades
        .where(
          (entry) =>
              entry.raceId == race &&
              _evolutionTeamKey(entry) == _team &&
              carComponentIds.contains(entry.componentId),
        )
        .map((entry) => entry.componentId!)
        .toSet();
  }
}

String _evolutionTeamKey(UpgradeEntry entry) {
  final key = carTeamKey(entry.teamId, entry.team);
  return key == 'neutral' ? 'api:${entry.teamId}' : key;
}

final _neverNotify = _NeverNotify();

class _NeverNotify extends ChangeNotifier {}
