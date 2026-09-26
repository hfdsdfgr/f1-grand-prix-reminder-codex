import 'package:flutter/material.dart';

import 'presentation.dart';

import '../core/language.dart';
import '../data/race_repository.dart';

class RaceFeedView extends StatefulWidget {
  final RaceRepository repository;
  final int? season;
  final Widget? emptyContent;
  final bool inlineFooter;
  final Widget Function(RaceFeed) builder;
  const RaceFeedView({
    super.key,
    required this.repository,
    required this.builder,
    this.season,
    this.emptyContent,
    this.inlineFooter = false,
  });
  @override
  State<RaceFeedView> createState() => _RaceFeedViewState();
}

class _RaceFeedViewState extends State<RaceFeedView> {
  late Future<RaceFeed> _future;
  RaceFeed? _last;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RaceFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.season != widget.season) {
      _last = null;
      _load();
    }
  }

  void _load() {
    _future = widget.repository.load(season: widget.season);
  }

  void _retry() => setState(_load);
  @override
  Widget build(BuildContext context) => FutureBuilder<RaceFeed>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return ContentState(tr(context, 'Loading races'), loading: true);
      }
      if (snapshot.hasData) _last = snapshot.data;
      if (snapshot.hasError && _last == null) {
        return ContentState(
          tr(context, 'Unable to load races'),
          detail: tr(context, 'Check your connection and try again.'),
          onRetry: _retry,
        );
      }
      final feed = _last!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (snapshot.hasError || feed.stale)
            ContentState(
              tr(context, 'Showing saved schedule. Times may have changed.'),
            ),
          if (feed.races.isEmpty)
            ContentState(
              tr(
                context,
                'No published races yet. Check back for the next schedule.',
              ),
            )
          else
            widget.builder(snapshot.hasError ? RaceFeed.staleCopy(feed) : feed),
          if (feed.races.isEmpty) ?widget.emptyContent,
          const SizedBox(height: 24),
          if (widget.inlineFooter)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${tr(context, 'Updated')} ${localDate(context, feed.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  onPressed: _retry,
                  tooltip: tr(context, 'Refresh'),
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            )
          else ...[
            Text(
              '${tr(context, 'Updated')} ${localDate(context, feed.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'Refresh')),
            ),
          ],
        ],
      );
    },
  );
}

String localDate(BuildContext context, DateTime time) {
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(time)}  ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(time), alwaysUse24HourFormat: true)}';
}
