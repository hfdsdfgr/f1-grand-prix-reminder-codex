import 'package:flutter/material.dart';

import '../core/language.dart';
import '../data/follow_service.dart';
import '../data/race_repository.dart';

/// Source-backed, season-specific context for the user's saved follows.
class FollowContext extends StatefulWidget {
  final RaceRepository repository;
  final FollowService? follows;
  final int season;
  const FollowContext({
    super.key,
    required this.repository,
    required this.season,
    this.follows,
  });

  @override
  State<FollowContext> createState() => _FollowContextState();
}

class _FollowContextState extends State<FollowContext> {
  late Future<SeasonRosterFeed> _roster = _load();

  Future<SeasonRosterFeed> _load() => widget.repository.roster(widget.season);

  @override
  void didUpdateWidget(FollowContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.season != widget.season) {
      _roster = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final follows = widget.follows;
    if (follows == null || (follows.drivers.isEmpty && follows.teams.isEmpty)) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: follows,
      builder: (context, _) => FutureBuilder<SeasonRosterFeed>(
        future: _roster,
        builder: (context, snapshot) {
          final roster = snapshot.data;
          if (roster == null) return const SizedBox.shrink();
          final entries = roster.entries
              .where(
                (entry) =>
                    follows.followsDriver(entry.driverId) ||
                    follows.followsTeam(entry.teamId),
              )
              .toList();
          if (entries.isEmpty) return const SizedBox.shrink();
          return Semantics(
            container: true,
            label:
                '${tr(context, 'Following this season')}: '
                '${entries.map((entry) => '${entry.driver}, ${entry.team}').join('; ')}',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'Following this season'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final entry in entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('${entry.driver} · ${entry.team}'),
                      ),
                    if (roster.stale)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          tr(
                            context,
                            'Showing saved follow context. It may have changed.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
