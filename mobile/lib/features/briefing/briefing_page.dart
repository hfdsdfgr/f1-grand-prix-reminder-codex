import 'package:flutter/material.dart';

import '../../shared/presentation.dart';
import '../../shared/editorial.dart';
import '../../shared/editorial_media.dart';
import '../races/race_detail_page.dart';

import '../../core/language.dart';
import '../../core/spoilers.dart';
import '../../data/follow_service.dart';
import '../../data/race_repository.dart';
import '../../shared/race_briefing_view.dart';

class BriefingPage extends StatefulWidget {
  final RaceRepository repository;
  final String? initialRaceId;
  final bool spoilerFree;
  final Set<String> revealedSessions;
  final ValueChanged<String>? onRevealSession;
  final FollowService? follows;
  const BriefingPage({
    super.key,
    required this.repository,
    this.initialRaceId,
    this.spoilerFree = false,
    this.revealedSessions = const {},
    this.onRevealSession,
    this.follows,
  });

  @override
  State<BriefingPage> createState() => _BriefingPageState();
}

class _BriefingPageState extends State<BriefingPage> {
  late String? _raceId = widget.initialRaceId;
  int _tab = 0;
  final Set<String> _revealed = {};
  int get _season =>
      int.tryParse(widget.initialRaceId?.split('-').first ?? '') ??
      DateTime.now().year;
  late Future<RaceFeed> _request = widget.repository.load(
    season: _season,
    summaries: false,
  );

  void _retry() => setState(() {
    _request = widget.repository.load(season: _season, summaries: false);
  });

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
            EditorialMediaView(
              repository: widget.repository,
              raceId: race.id,
              role: 'briefing',
              spoilerHidden: hidesRaceResult(
                enabled: widget.spoilerFree,
                phase: race.lifecyclePhase,
                raceId: race.id,
                revealedSessions: {...widget.revealedSessions, ..._revealed},
              ),
              child: EditorialHeader(
                title: 'Briefing',
                trailing: EditorialShare(
                  title:
                      '${tr(context, 'Briefing')} · ${tr(context, race.name)}',
                  sources: [race.source],
                ),
                eyebrow: [
                  if (race.round != null)
                    '${race.round} / ${race.totalRounds ?? snapshot.data!.races.map((r) => r.round ?? 0).fold<int>(0, (a, b) => a > b ? a : b)}',
                  tr(context, race.name),
                ].join('   '),
                subtitle: 'What happened and what it means.',
              ),
            ),
            EditorialTabs(
              labels: const [
                'Key stories',
                'Race result',
                'Quotes',
                'Analysis',
              ],
              selected: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
            const SizedBox(height: 12),
            if (_tab == 1 || _tab == 3)
              RaceDetailPage(
                key: ValueKey(
                  '${race.id}-$_tab-${Localizations.localeOf(context)}',
                ),
                race: race,
                repository: widget.repository,
                follows: widget.follows,
                section: _tab == 1 ? 'results' : 'analysis',
                spoilerHidden: hidesRaceResult(
                  enabled: widget.spoilerFree,
                  phase: race.lifecyclePhase,
                  raceId: race.id,
                  revealedSessions: {...widget.revealedSessions, ..._revealed},
                ),
                onReveal: () {
                  final key = spoilerSessionKey(race!.id);
                  setState(() => _revealed.add(key));
                  widget.onRevealSession?.call(key);
                },
              )
            else
              RaceBriefingView(
                repository: widget.repository,
                raceId: race.id,
                showTitle: false,
                quotesOnly: _tab == 2,
                spoilerHidden: hidesRaceResult(
                  enabled: widget.spoilerFree,
                  phase: race.lifecyclePhase,
                  raceId: race.id,
                  revealedSessions: {...widget.revealedSessions, ..._revealed},
                ),
                onReveal: () {
                  final key = spoilerSessionKey(race!.id);
                  setState(() => _revealed.add(key));
                  widget.onRevealSession?.call(key);
                },
                follows: widget.follows,
              ),
          ],
        ],
      );
    },
  );
}
