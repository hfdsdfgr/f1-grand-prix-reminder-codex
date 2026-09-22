import 'package:flutter/material.dart';

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
  String? _selectedUpgrade, _highlightedComponent, _highlightedTeam;
  bool _compareSpecification = false;
  late Future<EvolutionFeed> _request = _fetch();

  Future<EvolutionFeed> _fetch() => widget.raceId == null
      ? widget.repository.evolution(_season)
      : widget.repository.evolutionRace(widget.raceId!);

  void _load() => setState(() => _request = _fetch());

  void _selectUpgrade(UpgradeEntry entry) => setState(() {
    _selectedUpgrade = entry.id;
    _highlightedComponent = entry.componentId;
    _highlightedTeam = entry.teamId;
  });

  void _clearSelection() {
    _selectedUpgrade = null;
    _highlightedComponent = null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tr(context, 'Evolution'),
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 12),
      Text(tr(context, 'Follow what changes on the cars.')),
      const SizedBox(height: 24),
      if (widget.raceId == null) ...[
        CarViewer(
          enableGltf: widget.enableGltf,
          highlightedComponentId: _highlightedComponent,
          highlightedTeamId: _highlightedTeam,
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            IconButton(
              tooltip: tr(context, 'Previous season'),
              onPressed: _season > 1950
                  ? () {
                      _season--;
                      _team = null;
                      _race = null;
                      _highlightedTeam = null;
                      _clearSelection();
                      _compareSpecification = false;
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
                      _team = null;
                      _race = null;
                      _highlightedTeam = null;
                      _clearSelection();
                      _compareSpecification = false;
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
      FutureBuilder<EvolutionFeed>(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: tr(context, 'Loading upgrades'),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'Unable to load upgrades. Please retry.')),
                TextButton(onPressed: _load, child: Text(tr(context, 'Retry'))),
              ],
            );
          }
          final feed = snapshot.data!;
          return AnimatedBuilder(
            animation: widget.follows ?? _neverNotify,
            builder: (context, _) => _content(context, feed),
          );
        },
      ),
    ],
  );

  Widget _content(BuildContext context, EvolutionFeed feed) {
    final teams = {for (final u in feed.upgrades) u.teamId: u.team};
    final team = teams.containsKey(_team) ? _team : null;
    final teamEntries = feed.upgrades
        .where((u) => team == null || u.teamId == team)
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (feed.stale)
          Text(tr(context, 'Showing saved upgrades. They may have changed.')),
        if (feed.upgrades.isEmpty)
          Text(
            tr(context, 'No sourced upgrades are available for this season.'),
          ),
        if (feed.upgrades.isNotEmpty && widget.raceId == null) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('team-$_season-$team'),
            initialValue: team,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(context, 'Team')),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(tr(context, 'All teams')),
              ),
              for (final t in teams.entries)
                DropdownMenuItem(value: t.key, child: Text(t.value)),
            ],
            onChanged: (value) => setState(() {
              _team = value;
              _race = null;
              _highlightedTeam = value;
              _clearSelection();
              _compareSpecification = false;
            }),
          ),
          const SizedBox(height: 16),
        ],
        if (feed.timeline.isNotEmpty || feed.upgrades.isNotEmpty) ...[
          Text(
            tr(context, 'Season Evolution'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
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
                    _compareSpecification = false;
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
                              _compareSpecification = false;
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
                _compareSpecification = false;
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
                previous: tr(context, 'Launch specification'),
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
                geometryAvailable: false,
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
          for (final entry in entries)
            _UpgradeDetails(
              key: ValueKey(entry.id),
              entry: entry,
              selected: entry.id == _selectedUpgrade,
              mappedTo3d: carComponentIds.contains(entry.componentId),
              onSelected: () => _selectUpgrade(entry),
            ),
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
}

final _neverNotify = _NeverNotify();

class _NeverNotify extends ChangeNotifier {}

class _UpgradeDetails extends StatelessWidget {
  final UpgradeEntry entry;
  final bool selected;
  final bool mappedTo3d;
  final VoidCallback onSelected;
  const _UpgradeDetails({
    super.key,
    required this.entry,
    required this.selected,
    required this.mappedTo3d,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => ExpansionTile(
    onExpansionChanged: (expanded) {
      if (expanded) onSelected();
    },
    leading: Icon(
      selected ? Icons.adjust : Icons.circle_outlined,
      color: selected ? Theme.of(context).colorScheme.primary : null,
      size: 18,
    ),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 24),
    title: Text('${entry.team} · ${tr(context, entry.component)}'),
    subtitle: Text(
      '${tr(context, entry.race ?? 'Not available')} · ${tr(context, entry.status)}',
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.title, style: Theme.of(context).textTheme.titleLarge),
            for (final field in [
              ('Change', entry.change),
              ('Goal', entry.goal),
              ('Expected effect', entry.expectedEffect),
            ])
              if (field.$2 != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('${tr(context, field.$1)}: ${field.$2}'),
                ),
            if (!mappedTo3d)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  tr(
                    context,
                    'This upgrade has no compatible 3D component mapping.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'Sources'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final source in entry.sources)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.provider ?? ''),
                    SelectableText(source.url),
                    if (source.publishedAt != null)
                      Text(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(source.publishedAt!),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
