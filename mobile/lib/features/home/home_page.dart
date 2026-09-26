import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../shared/editorial.dart';
import '../../shared/editorial_media.dart';
import 'latest_section.dart';

import '../../core/language.dart';
import '../../core/spoilers.dart';
import '../../data/race_repository.dart';
import '../../data/follow_service.dart';
import '../../data/reminder_service.dart';
import 'reminder_row.dart';
import '../../shared/race_feed_view.dart';
import '../../shared/follow_context.dart';
import '../races/race_detail_page.dart';

class HomePage extends StatelessWidget {
  final RaceRepository repository;
  final ReminderService? reminders;
  final Future<void> Function(bool)? syncReminders;
  final bool spoilerFree;
  final Set<String> revealedSessions;
  final ValueChanged<String>? onRevealSession;
  final FollowService? follows;
  final ValueChanged<String?>? onOpenBriefing;
  const HomePage({
    super.key,
    required this.repository,
    this.reminders,
    this.syncReminders,
    this.spoilerFree = false,
    this.revealedSessions = const {},
    this.onRevealSession,
    this.follows,
    this.onOpenBriefing,
  });
  @override
  Widget build(BuildContext context) => RaceFeedView(
    repository: repository,
    inlineFooter: true,
    emptyContent: LatestSection(
      repository: repository,
      season: DateTime.now().year,
      spoilerFree: spoilerFree,
      revealedSessions: revealedSessions,
      onRevealSession: onRevealSession,
      onOpenBriefing: onOpenBriefing,
      follows: follows,
    ),
    builder: (feed) {
      final race = feed.races.first;
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: EditorialLabel('GrandPrixReminder')),
              Text('${race.season}', style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 24),
          EditorialMediaView(
            repository: repository,
            raceId: race.id,
            role: 'home',
            spoilerHidden:
                spoilerFree &&
                !revealedSessions.contains(spoilerSessionKey(race.id)),
            heroHeight: 370,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EditorialHeader(
                  title: race.name,
                  eyebrow: [
                    if (race.round != null)
                      '${race.round}${race.totalRounds == null ? '' : ' / ${race.totalRounds}'}',
                    tr(
                      context,
                      race.lifecyclePhase == 'race_weekend'
                          ? 'Race weekend'
                          : 'Next Grand Prix',
                    ),
                  ].join('  /  '),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(context, race.circuit),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    if (race.circuitLayout case final layout?)
                      SizedBox(
                        width: 48,
                        height: 32,
                        child: SvgPicture.asset(
                          layout.assetPath,
                          semanticsLabel: tr(context, race.circuit),
                          colorFilter: ColorFilter.mode(
                            theme.colorScheme.onSurface,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                if (race.startsAt != null)
                  Text(
                    localDate(context, race.startsAt!),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
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
              '${tr(context, 'Your local time')} (${race.startsAt!.timeZoneName})',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Countdown(startsAt: race.startsAt!),
          ] else
            Text('${race.date} · ${tr(context, 'Start time to be confirmed')}'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: EditorialLabel('Weekend schedule')),
              EditorialLabel('Local time'),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          for (final session in race.sessions) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final time = session.startsAt;
                  final locale = Localizations.localeOf(context)
                      .toLanguageTag();
                  final kind = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, session.kind).toUpperCase(),
                        style: theme.textTheme.labelLarge,
                      ),
                      if (session.status != 'scheduled')
                        Text(
                          tr(context, sessionStatusLabel(session.status)),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  );
                  if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        kind,
                        Text(
                          time == null
                              ? tr(context, 'Not available')
                              : localDate(context, time),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 35,
                        child: Text(
                          time == null
                              ? '—'
                              : DateFormat(
                                  'E',
                                  locale,
                                ).format(time).toUpperCase(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      SizedBox(
                        width: 65,
                        child: Text(
                          time == null
                              ? '—'
                              : DateFormat(
                                  'd MMM',
                                  locale,
                                ).format(time).toUpperCase(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      SizedBox(
                        width: 55,
                        child: Text(
                          time == null
                              ? '—'
                              : DateFormat('HH:mm', locale).format(time),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Expanded(child: kind),
                    ],
                  );
                },
              ),
            ),
            const Divider(),
          ],
          const Divider(),
          const SizedBox(height: 16),
          LatestSection(
            repository: repository,
            season: race.season > DateTime.now().year
                ? DateTime.now().year
                : race.season,
            spoilerFree: spoilerFree,
            revealedSessions: revealedSessions,
            onRevealSession: onRevealSession,
            onOpenBriefing: onOpenBriefing,
            follows: follows,
          ),
          const SizedBox(height: 20),
          InkWell(
            key: const ValueKey('home-details'),
            onTap: () => Navigator.of(context).push(
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
                  follows: follows,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'View details'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
          const Divider(),
          ReminderRow(
            race: race,
            service: reminders,
            stale: feed.stale,
            syncReminders: syncReminders,
          ),
          FollowContext(
            repository: repository,
            season: race.season,
            follows: follows,
          ),
          if (race.sessions.isEmpty)
            Text(tr(context, 'Session times have not been published.')),
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
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final remaining = widget.startsAt.difference(now);
    if (remaining <= Duration.zero) {
      return Text(tr(context, 'Scheduled start reached'));
    }
    final values = [
      remaining.inDays,
      remaining.inHours % 24,
      remaining.inMinutes % 60,
    ];
    return Semantics(
      label: countdownLabel(
        widget.startsAt,
        now,
        language: Localizations.localeOf(context).languageCode,
      ),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label ?? tr(context, 'Race starts in'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 20),
                      decoration: i == 0
                          ? null
                          : BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                  width: .5,
                                ),
                              ),
                            ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            values[i].toString().padLeft(2, '0'),
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 40,
                                  fontFeatures: [
                                    const FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                          EditorialLabel(['Days', 'Hours', 'Minutes'][i]),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
