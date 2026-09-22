import 'package:flutter/material.dart';

import '../../shared/presentation.dart';

import '../../core/language.dart';
import '../../core/spoilers.dart';
import '../../data/follow_service.dart';
import '../../data/race_repository.dart';
import '../../shared/race_briefing_view.dart';

class BriefingPage extends StatefulWidget {
  final RaceRepository repository;
  final bool spoilerFree;
  final Set<String> revealedSessions;
  final ValueChanged<String>? onRevealSession;
  final FollowService? follows;
  const BriefingPage({
    super.key,
    required this.repository,
    this.spoilerFree = false,
    this.revealedSessions = const {},
    this.onRevealSession,
    this.follows,
  });

  @override
  State<BriefingPage> createState() => _BriefingPageState();
}

class _BriefingPageState extends State<BriefingPage> {
  String? _raceId;
  late Future<RaceFeed> _request = widget.repository.load(
    season: DateTime.now().year,
    summaries: false,
  );

  void _retry() => setState(
    () => _request = widget.repository.load(
      season: DateTime.now().year,
      summaries: false,
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<RaceFeed>(
    future: _request,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return ContentState(
          tr(context, 'Loading race briefing'),
          loading: true,
        );
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return ContentState(
          tr(context, 'Unable to load race briefing. Please try again.'),
          onRetry: _retry,
        );
      }
      final completed = snapshot.data!.races
          .where((race) => race.lifecyclePhase == 'post_race')
          .toList();
      Race? race;
      for (final item in completed) {
        if (item.id == _raceId) race = item;
      }
      race ??= completed.isEmpty ? null : completed.last;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Briefing'),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          if (race == null)
            ContentState(
              tr(context, 'No completed race is available for briefing.'),
            )
          else ...[
            if (completed.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: race.id,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'Grand Prix'),
                ),
                items: [
                  for (final item in completed)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(tr(context, item.name)),
                    ),
                ],
                onChanged: (value) => setState(() => _raceId = value),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              tr(context, race.name),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            RaceBriefingView(
              repository: widget.repository,
              raceId: race.id,
              showTitle: false,
              spoilerHidden: hidesRaceResult(
                enabled: widget.spoilerFree,
                phase: race.lifecyclePhase,
                raceId: race.id,
                revealedSessions: widget.revealedSessions,
              ),
              onReveal: () =>
                  widget.onRevealSession?.call(spoilerSessionKey(race!.id)),
              follows: widget.follows,
            ),
          ],
        ],
      );
    },
  );
}
