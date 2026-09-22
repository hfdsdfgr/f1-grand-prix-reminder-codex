import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'presentation.dart';

import '../core/language.dart';
import '../data/follow_service.dart';
import '../data/race_repository.dart';

final _neverNotify = _NeverNotify();

class RaceBriefingView extends StatefulWidget {
  final RaceRepository repository;
  final String raceId;
  final bool showTitle;
  final bool spoilerHidden;
  final VoidCallback? onReveal;
  final FollowService? follows;
  const RaceBriefingView({
    super.key,
    required this.repository,
    required this.raceId,
    this.showTitle = true,
    this.spoilerHidden = false,
    this.onReveal,
    this.follows,
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
        return ContentState(
          tr(context, 'Loading race briefing'),
          loading: true,
        );
      }
      if (briefing == null) {
        return ContentState(
          tr(context, 'Unable to load race briefing. Please try again.'),
          onRetry: _retry,
        );
      }
      if (widget.spoilerHidden) {
        return _BriefingSpoilerGate(onReveal: widget.onReveal);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTitle) ...[
            SectionHeading(tr(context, 'Briefing')),
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
              child: ContentState(
                tr(context, 'Showing saved briefing. It may have changed.'),
              ),
            ),
          const SizedBox(height: 12),
          if (briefing.insights.isEmpty)
            ContentState(
              tr(context, 'No verified briefing is available for this race.'),
            ),
          AnimatedBuilder(
            animation: widget.follows ?? _neverNotify,
            builder: (context, _) {
              final insights = [...briefing.insights]
                ..sort((a, b) => _followScore(b).compareTo(_followScore(a)));
              return Column(
                children: [
                  for (final insight in insights) _Insight(insight: insight),
                ],
              );
            },
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
                child: SourceReference(
                  publisher: source.provider,
                  url: source.url,
                ),
              ),
          ],
        ],
      );
    },
  );

  int _followScore(BriefingInsight insight) {
    final follows = widget.follows;
    if (follows == null) return 0;
    final content = '${insight.topic} ${insight.detail}'.toLowerCase();
    return [
          ...follows.drivers,
          ...follows.teams,
        ].any((entry) => content.contains(entry.name.toLowerCase()))
        ? 1
        : 0;
  }
}

class _Insight extends StatelessWidget {
  final BriefingInsight insight;
  const _Insight({required this.insight});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '${tr(context, insight.topic)}. ${insight.detail}',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: RaceSpace.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, insight.topic),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: RaceSpace.small),
            Text(insight.detail, style: Theme.of(context).textTheme.bodyLarge),
            for (final source in insight.sources)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SourceReference(
                  publisher: source.provider,
                  url: source.url,
                ),
              ),
            const SizedBox(height: RaceSpace.large),
            const Divider(),
          ],
        ),
      ),
    ),
  );
}

class _BriefingSpoilerGate extends StatelessWidget {
  final VoidCallback? onReveal;
  const _BriefingSpoilerGate({this.onReveal});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeading(tr(context, 'Briefing hidden')),
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

class _NeverNotify extends ChangeNotifier {}
