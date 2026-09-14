import 'package:flutter/material.dart';

import '../core/language.dart';
import '../data/race_repository.dart';

class RaceFeedView extends StatefulWidget {
  final RaceRepository repository;
  final int? season;
  final Widget Function(RaceFeed) builder;
  const RaceFeedView({
    super.key,
    required this.repository,
    required this.builder,
    this.season,
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
        return Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: CircularProgressIndicator(
              semanticsLabel: tr(context, 'Loading races'),
            ),
          ),
        );
      }
      if (snapshot.hasData) _last = snapshot.data;
      if (snapshot.hasError && _last == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Unable to load races'),
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 16),
            Text(tr(context, 'Check your connection and try again.')),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'Retry')),
            ),
          ],
        );
      }
      final feed = _last!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (snapshot.hasError || feed.stale)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                tr(context, 'Showing saved schedule. Times may have changed.'),
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (feed.races.isEmpty)
            Text(
              tr(
                context,
                'No published races yet. Check back for the next schedule.',
              ),
            )
          else
            widget.builder(snapshot.hasError ? RaceFeed.staleCopy(feed) : feed),
          const SizedBox(height: 24),
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
      );
    },
  );
}

String localDate(BuildContext context, DateTime time) {
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(time)}  ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(time), alwaysUse24HourFormat: true)}';
}
