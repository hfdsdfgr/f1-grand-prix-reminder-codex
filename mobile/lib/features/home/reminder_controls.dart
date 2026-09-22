import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../data/race_repository.dart';
import '../../data/reminder_service.dart';
import '../../shared/race_feed_view.dart';

class ReminderControls extends StatefulWidget {
  final Race race;
  final ReminderService? service;
  final bool stale;
  final Future<void> Function(bool)? syncReminders;
  const ReminderControls({
    super.key,
    required this.race,
    this.service,
    required this.stale,
    this.syncReminders,
  });
  @override
  State<ReminderControls> createState() => _ReminderControlsState();
}

class _ReminderControlsState extends State<ReminderControls> {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.notifications_outlined),
        label: Text(tr(context, 'Race reminders')),
        onPressed: () async {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => ReminderSheet(
              race: widget.race,
              service: widget.service,
              stale: widget.stale,
              syncReminders: widget.syncReminders,
            ),
          );
          if (mounted) setState(() {});
        },
      ),
      Text(
        tr(
          context,
          widget.service?.automaticEnabled == false
              ? 'Automatic race reminders are off.'
              : 'Automatic race reminders: 1 hour before each race.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (widget.service?.supported == true) ...[
        Text(
          '${tr(context, 'Scheduled races')}: ${widget.service!.scheduledRaces}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.service!.syncMessage case final message?)
          Text(
            tr(context, message),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
      if (widget.service?.supported == true)
        for (final session in widget.race.sessions.where(
          (s) => reminderKinds.contains(s.kind) && s.startsAt != null,
        ))
          if (widget.service!.saved(widget.race.id, session.kind)
              case final record?)
            Text(
              '${tr(context, session.kind)} · ${record['minutes']} ${tr(context, 'minutes before start')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
    ],
  );
}

class ReminderSheet extends StatefulWidget {
  final Race race;
  final ReminderService? service;
  final bool stale;
  final Future<void> Function(bool)? syncReminders;
  const ReminderSheet({
    super.key,
    required this.race,
    this.service,
    required this.stale,
    this.syncReminders,
  });
  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  late final List<RaceSession> _sessions = widget.race.sessions
      .where((s) => reminderKinds.contains(s.kind) && s.startsAt != null)
      .toList();
  int _session = 0;
  int _preset = 60;
  final _custom = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  void _restore() {
    if (_sessions.isEmpty) return;
    final record = widget.service?.saved(
      widget.race.id,
      _sessions[_session].kind,
    );
    final minutes = record?['minutes'] as int? ?? 60;
    _preset = [15, 60, 1440].contains(minutes) ? minutes : -1;
    _custom.text = '$minutes';
    _message = null;
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _submit({bool cancel = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final session = _sessions[_session];
      if (cancel) {
        await widget.service!.cancel(widget.race.id, session.kind);
      } else {
        final minutes = _preset == -1
            ? int.tryParse(_custom.text.trim())
            : _preset;
        if (minutes == null) {
          throw const ReminderException('Choose 1 to 10080 minutes.');
        }
        await widget.service!.save(
          widget.race,
          session,
          minutes,
          Localizations.localeOf(context).languageCode,
        );
      }
      await widget.syncReminders?.call(false);
      if (mounted) {
        setState(
          () =>
              _message = cancel ? 'Reminder cancelled.' : 'Reminder scheduled.',
        );
      }
    } on ReminderException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Unable to save reminder. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _automatic(bool enabled) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service!.setAutomatic(enabled);
      await widget.syncReminders?.call(enabled);
      if (mounted) setState(() => _message = widget.service!.syncMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Unable to save reminder. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = widget.service?.supported == true;
    final existing = _sessions.isEmpty
        ? null
        : widget.service?.saved(widget.race.id, _sessions[_session].kind);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        RaceSpace.large,
        RaceSpace.large,
        RaceSpace.large,
        RaceSpace.large + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Race reminders'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              tr(context, 'Automatically remind me of upcoming races'),
            ),
            subtitle: Text(
              tr(
                context,
                'One hour before every published race, including the next race.',
              ),
            ),
            value: widget.service?.automaticEnabled ?? true,
            onChanged: !supported || _busy ? null : _automatic,
          ),
          Text(tr(context, 'Session settings below override this race only.')),
          if (supported)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _automatic(widget.service!.automaticEnabled),
              child: Text(tr(context, 'Check permissions and sync reminders')),
            ),
          if (!supported)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                tr(
                  context,
                  'Local reminders are available in the Android and iOS apps.',
                ),
              ),
            ),
          if (widget.stale)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                tr(context, 'Refresh the schedule before creating a reminder.'),
              ),
            ),
          if (_sessions.isEmpty)
            Text(tr(context, 'Session times have not been published.'))
          else ...[
            const SizedBox(height: 24),
            DropdownButtonFormField<int>(
              initialValue: _session,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(context, 'Session')),
              items: [
                for (var i = 0; i < _sessions.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(tr(context, _sessions[i].kind)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _session = value!;
                      _restore();
                    }),
            ),
            const SizedBox(height: 12),
            Text(localDate(context, _sessions[_session].startsAt!)),
            if (existing != null) ...[
              Text(
                '${tr(context, 'Saved reminder')}: ${existing['minutes']} ${tr(context, 'minutes before start')}',
              ),
              if (existing['start'] !=
                  _sessions[_session].startsAt!.toUtc().toIso8601String())
                Text(
                  tr(
                    context,
                    'Schedule changed. Save again to update your reminder.',
                  ),
                ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: ValueKey('$_session-$_preset'),
              initialValue: _preset,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(context, 'Remind me')),
              items: [
                DropdownMenuItem(
                  value: 1440,
                  child: Text(tr(context, '24 hours before')),
                ),
                DropdownMenuItem(
                  value: 60,
                  child: Text(tr(context, '1 hour before')),
                ),
                DropdownMenuItem(
                  value: 15,
                  child: Text(tr(context, '15 minutes before')),
                ),
                DropdownMenuItem(value: -1, child: Text(tr(context, 'Custom'))),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _preset = value!),
            ),
            if (_preset == -1)
              TextField(
                controller: _custom,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr(context, 'Minutes before start'),
                  helperText: tr(context, 'Choose 1 to 10080 minutes.'),
                ),
              ),
            const SizedBox(height: 24),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(tr(context, _message!))),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: !supported || widget.stale || _busy
                      ? null
                      : () => _submit(),
                  child: Text(tr(context, _busy ? 'Saving…' : 'Save reminder')),
                ),
                if (existing != null)
                  TextButton(
                    onPressed: !supported || _busy
                        ? null
                        : () => _submit(cancel: true),
                    child: Text(tr(context, 'Cancel reminder')),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(tr(context, 'Close')),
          ),
        ],
      ),
    );
  }
}
