import 'package:flutter/material.dart';

import 'presentation.dart';
import 'editorial.dart';
import 'editorial_media.dart';

import '../core/language.dart';
import '../data/follow_service.dart';
import '../data/race_repository.dart';

final _neverNotify = _NeverNotify();

class RaceBriefingView extends StatefulWidget {
  final RaceRepository repository;
  final String raceId;
  final bool showTitle;
  final bool quotesOnly;
  final bool spoilerHidden;
  final VoidCallback? onReveal;
  final FollowService? follows;
  const RaceBriefingView({
    super.key,
    required this.repository,
    required this.raceId,
    this.showTitle = true,
    this.quotesOnly = false,
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
  Future<List<EditorialMedia>> _loadMedia() => widget.repository
      .media(widget.raceId)
      .catchError((_) => <EditorialMedia>[]);
  late Future<List<EditorialMedia>> _media = _loadMedia();
  String? _language;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).toLanguageTag();
    if (_language != null && _language != language) {
      _saved = null;
      _request = widget.repository.briefing(widget.raceId);
      _media = _loadMedia();
    }
    _language = language;
  }

  @override
  void didUpdateWidget(RaceBriefingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raceId != widget.raceId) {
      _saved = null;
      _request = widget.repository.briefing(widget.raceId);
      _media = _loadMedia();
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
      final sources = <String, BriefingSource>{
        for (final source in briefing.sources) source.url: source,
        for (final insight in briefing.insights)
          for (final source in insight.sources) source.url: source,
      }.values.toList();
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
              final insights = [
                ...briefing.insights.where(
                  (i) =>
                      !widget.quotesOnly ||
                      (i.field == 'key_quotes' && i.evidence.isNotEmpty),
                ),
              ]..sort((a, b) => _followScore(b).compareTo(_followScore(a)));
              return FutureBuilder<List<EditorialMedia>>(
                future: _media,
                builder: (context, mediaSnapshot) {
                  final media = mediaSnapshot.data ?? <EditorialMedia>[];
                  return Column(
                    children: [
                      if (insights.isEmpty && widget.quotesOnly)
                        ContentState(
                          tr(context, 'No verified quotes are available.'),
                        ),
                      for (var i = 0; i < insights.length; i++)
                        EditorialRow(
                          number: i + 1,
                          thumbnail: _thumbnail(media, insights[i].topic),
                          title: insights[i].topic,
                          detail: widget.quotesOnly
                              ? insights[i].evidence
                                    .map((e) => e.quote)
                                    .join('\n\n')
                              : insights[i].detail,
                          onTap: () => showEditorialDetail(
                            context,
                            title: tr(context, insights[i].topic),
                            body: widget.quotesOnly
                                ? insights[i].evidence
                                      .map((e) => e.quote)
                                      .join('\n\n')
                                : insights[i].detail,
                            sources: [
                              for (final evidence in insights[i].evidence) ...[
                                if (!widget.quotesOnly)
                                  EvidenceField(
                                    'Original evidence',
                                    evidence.quote,
                                  ),
                                SourceReference(
                                  publisher: evidence.source.provider,
                                  url: evidence.source.url,
                                ),
                              ],
                              for (final source in insights[i].sources)
                                SourceReference(
                                  publisher: source.provider,
                                  url: source.url,
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('briefing-sources'),
              onPressed: () => _showSources(context, sources),
              icon: const Icon(Icons.source_outlined, size: 18),
              label: Text('${tr(context, 'Sources')} (${sources.length})'),
            ),
          ],
        ],
      );
    },
  );

  Widget? _thumbnail(List<EditorialMedia> media, String topic) {
    final item = media
        .where((m) => m.role == 'story' && m.topic == topic)
        .firstOrNull;
    return item == null ? null : EditorialMediaImage(item: item, compact: true);
  }

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

  void _showSources(BuildContext context, List<BriefingSource> sources) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        shrinkWrap: true,
        children: [
          Text(
            tr(context, 'Sources'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          for (final source in sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SourceReference(
                publisher: source.provider,
                url: source.url,
              ),
            ),
        ],
      ),
    );
  }
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
