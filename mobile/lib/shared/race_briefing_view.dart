import 'package:flutter/material.dart';

import '../core/language.dart';
import '../data/race_repository.dart';

class RaceBriefingView extends StatefulWidget {
  final RaceRepository repository;
  final String raceId;
  final bool showTitle;
  const RaceBriefingView({
    super.key,
    required this.repository,
    required this.raceId,
    this.showTitle = true,
  });

  @override
  State<RaceBriefingView> createState() => _RaceBriefingViewState();
}

class _RaceBriefingViewState extends State<RaceBriefingView> {
  late Future<RaceBriefingFeed> _request = widget.repository.briefing(
    widget.raceId,
  );
  RaceBriefingFeed? _saved;

  @override
  void didUpdateWidget(RaceBriefingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raceId != widget.raceId) {
      _saved = null;
      _request = widget.repository.briefing(widget.raceId);
    }
  }

  void _retry() =>
      setState(() => _request = widget.repository.briefing(widget.raceId));

  @override
  Widget build(BuildContext context) => FutureBuilder<RaceBriefingFeed>(
    future: _request,
    builder: (context, snapshot) {
      if (snapshot.hasData) _saved = snapshot.data;
      final briefing = snapshot.data ?? _saved;
      if (snapshot.connectionState == ConnectionState.waiting &&
          briefing == null) {
        return Center(
          child: CircularProgressIndicator(
            semanticsLabel: tr(context, 'Loading race briefing'),
          ),
        );
      }
      if (briefing == null) {
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTitle) ...[
            Text(
              tr(context, 'Briefing'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            tr(
              context,
              'Verified driver and team insights, with original sources.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (briefing.stale || snapshot.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                tr(context, 'Showing saved briefing. It may have changed.'),
              ),
            ),
          const SizedBox(height: 12),
          if (briefing.insights.isEmpty)
            Text(
              tr(context, 'No verified briefing is available for this race.'),
            ),
          for (final insight in briefing.insights)
            Semantics(
              container: true,
              label: '${tr(context, insight.topic)}. ${insight.detail}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, insight.topic),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(insight.detail),
                    ],
                  ),
                ),
              ),
            ),
          if (briefing.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tr(context, 'Sources'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final source in briefing.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (source.provider != null) Text(source.provider!),
                    SelectableText(
                      source.url,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ],
      );
    },
  );
}
