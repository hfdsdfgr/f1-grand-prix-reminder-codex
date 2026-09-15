import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../data/race_repository.dart';
import '../../shared/race_briefing_view.dart';

class BriefingPage extends StatefulWidget {
  final RaceRepository repository;
  const BriefingPage({super.key, required this.repository});

  @override
  State<BriefingPage> createState() => _BriefingPageState();
}

class _BriefingPageState extends State<BriefingPage> {
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
        return Center(
          child: CircularProgressIndicator(
            semanticsLabel: tr(context, 'Loading race briefing'),
          ),
        );
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Unable to load race briefing. Please try again.'),
            ),
            TextButton(onPressed: _retry, child: Text(tr(context, 'Retry'))),
          ],
        );
      }
      final completed = snapshot.data!.races
          .where((race) => race.lifecyclePhase == 'post_race')
          .toList();
      final race = completed.isEmpty ? null : completed.last;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Briefing'),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          if (race == null)
            Text(tr(context, 'No completed race is available for briefing.'))
          else ...[
            Text(
              tr(context, race.name),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            RaceBriefingView(
              repository: widget.repository,
              raceId: race.id,
              showTitle: false,
            ),
          ],
        ],
      );
    },
  );
}
