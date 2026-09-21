import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../data/race_repository.dart';
import 'car_viewer.dart';

class EvolutionPage extends StatefulWidget {
  final RaceRepository repository;
  final bool enableGltf;
  const EvolutionPage({
    super.key,
    required this.repository,
    this.enableGltf = true,
  });

  @override
  State<EvolutionPage> createState() => _EvolutionPageState();
}

class _EvolutionPageState extends State<EvolutionPage> {
  int _season = DateTime.now().year;
  String? _team, _race;
  late Future<EvolutionFeed> _request = widget.repository.evolution(_season);

  void _load() => setState(() {
    _request = widget.repository.evolution(_season);
  });

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
      CarViewer(enableGltf: widget.enableGltf),
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
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      const SizedBox(height: 24),
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
          final teams = {for (final u in feed.upgrades) u.teamId: u.team};
          final team = teams.containsKey(_team) ? _team : null;
          final teamEntries = feed.upgrades
              .where((u) => team == null || u.teamId == team)
              .toList();
          final races = {
            for (final u in teamEntries)
              if (u.raceId != null) u.raceId!: u.race!,
          };
          final race = races.containsKey(_race) ? _race : null;
          final entries = teamEntries.where(
            (u) => race == null || u.raceId == race,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (feed.stale)
                Text(
                  tr(context, 'Showing saved upgrades. They may have changed.'),
                ),
              if (feed.upgrades.isEmpty)
                Text(
                  tr(
                    context,
                    'No sourced upgrades are available for this season.',
                  ),
                ),
              if (feed.upgrades.isNotEmpty) ...[
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
                  }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('race-$_season-$team-$race'),
                  initialValue: race,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Grand Prix'),
                  ),
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
                  onChanged: (value) => setState(() => _race = value),
                ),
                const SizedBox(height: 32),
                Text(
                  tr(context, 'Upgrade timeline'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                for (final entry in entries)
                  _UpgradeDetails(key: ValueKey(entry.id), entry: entry),
              ],
              TextButton.icon(
                onPressed: _load,
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

class _UpgradeDetails extends StatelessWidget {
  final UpgradeEntry entry;
  const _UpgradeDetails({super.key, required this.entry});

  @override
  Widget build(BuildContext context) => ExpansionTile(
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
