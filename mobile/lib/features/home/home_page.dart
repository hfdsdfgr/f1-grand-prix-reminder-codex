import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/spoilers.dart';
import '../../data/race_repository.dart';
import '../../data/reminder_service.dart';
import 'reminder_controls.dart';
import '../../shared/race_feed_view.dart';
import '../races/race_detail_page.dart';

class HomePage extends StatelessWidget {
  final RaceRepository repository;
  final ReminderService? reminders;
  final Future<void> Function(bool)? syncReminders;
  final bool spoilerFree;
  final Set<String> revealedSessions;
  final ValueChanged<String>? onRevealSession;
  const HomePage({
    super.key,
    required this.repository,
    this.reminders,
    this.syncReminders,
    this.spoilerFree = false,
    this.revealedSessions = const {},
    this.onRevealSession,
  });
  @override
  Widget build(BuildContext context) => RaceFeedView(
    repository: repository,
    builder: (feed) {
      final race = feed.races.first;
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              context,
              race.lifecyclePhase == 'race_weekend'
                  ? 'Race weekend'
                  : 'Next Grand Prix',
            ),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(tr(context, race.name), style: theme.textTheme.displaySmall),
          const SizedBox(height: 16),
          Text(
            tr(context, race.circuit),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          if (race.lifecyclePhase == 'race_weekend') ...[
            if (race.currentSession case final current?) ...[
              Text(
                tr(context, 'Current session'),
                style: theme.textTheme.bodySmall,
              ),
              Text(
                tr(context, current.kind),
                style: theme.textTheme.headlineMedium,
              ),
              Text(
                tr(context, sessionStatusLabel(current.status)),
                style: TextStyle(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
            ],
            if (race.nextSession case final next?) ...[
              Text(
                '${tr(context, 'Next session')} · ${tr(context, next.kind)}',
                style: theme.textTheme.titleLarge,
              ),
              if (next.startsAt != null) ...[
                Text(localDate(context, next.startsAt!)),
                const SizedBox(height: 16),
                Countdown(
                  startsAt: next.startsAt!,
                  label: tr(context, 'Next session starts in'),
                ),
              ],
            ],
          ] else if (race.startsAt != null) ...[
            Text(
              localDate(context, race.startsAt!),
              style: theme.textTheme.titleLarge,
            ),
            Text(
              '${tr(context, 'Your local time')} (${race.startsAt!.timeZoneName})',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Countdown(startsAt: race.startsAt!),
          ] else
            Text('${race.date} · ${tr(context, 'Start time to be confirmed')}'),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RaceDetailPage(
                  race: race,
                  repository: repository,
                  reminders: reminders,
                  syncReminders: syncReminders,
                  spoilerHidden: hidesRaceResult(
                    enabled: spoilerFree,
                    phase: race.lifecyclePhase,
                    raceId: race.id,
                    revealedSessions: revealedSessions,
                  ),
                  onReveal: () =>
                      onRevealSession?.call(spoilerSessionKey(race.id)),
                ),
              ),
            ),
            icon: const Icon(Icons.arrow_forward),
            label: Text(tr(context, 'View details')),
          ),
          const SizedBox(height: 24),
          ReminderControls(
            race: race,
            service: reminders,
            stale: feed.stale,
            syncReminders: syncReminders,
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 32),
          Text(
            tr(context, 'Race weekend'),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          for (final session in race.sessions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 24,
                runSpacing: 8,
                children: [
                  Text(
                    tr(context, session.kind),
                    style: TextStyle(
                      fontWeight: session.kind == 'Race'
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        session.startsAt == null
                            ? tr(context, 'Not available')
                            : localDate(context, session.startsAt!),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        tr(context, sessionStatusLabel(session.status)),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (race.sessions.isEmpty)
            Text(tr(context, 'Session times have not been published.')),
          const SizedBox(height: 24),
          Text(
            tr(context, 'Source: Jolpica F1'),
            style: theme.textTheme.bodySmall,
          ),
          SelectableText(race.source, style: theme.textTheme.bodySmall),
        ],
      );
    },
  );
}

String countdownLabel(DateTime start, DateTime now, {String language = 'en'}) {
  final remaining = start.difference(now);
  if (remaining.isNegative || remaining == Duration.zero) {
    return translate(language, 'Scheduled start reached');
  }
  if (language == 'zh') {
    return '${remaining.inDays}天  ${remaining.inHours % 24}小时  ${remaining.inMinutes % 60}分';
  }
  return '${remaining.inDays}d  ${remaining.inHours % 24}h  ${remaining.inMinutes % 60}m';
}

class Countdown extends StatefulWidget {
  final DateTime startsAt;
  final String? label;
  const Countdown({super.key, required this.startsAt, this.label});
  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late final Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.label ?? tr(context, 'Race starts in')),
      const SizedBox(height: 8),
      Text(
        countdownLabel(
          widget.startsAt,
          DateTime.now(),
          language: Localizations.localeOf(context).languageCode,
        ),
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontFeatures: [const FontFeature.tabularFigures()]),
      ),
    ],
  );
}
