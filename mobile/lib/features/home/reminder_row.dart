import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../data/race_repository.dart';
import '../../data/reminder_service.dart';
import 'reminder_controls.dart';

class ReminderRow extends StatefulWidget {
  final Race race;
  final ReminderService? service;
  final bool stale;
  final Future<void> Function(bool)? syncReminders;
  const ReminderRow({
    super.key,
    required this.race,
    this.service,
    required this.stale,
    this.syncReminders,
  });

  @override
  State<ReminderRow> createState() => _ReminderRowState();
}

class _ReminderRowState extends State<ReminderRow> with WidgetsBindingObserver {
  late Future<String?> _permission = _readPermission();

  Future<String?> _readPermission() =>
      widget.service?.permissionIssue() ??
      Future.value(
        'Local reminders are available in the Android and iOS apps.',
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(ReminderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // App-level reminder sync can change permissions for the same race/service.
    _permission = _readPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() => setState(() {
    _permission = _readPermission();
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _permission,
    builder: (context, snapshot) {
      final ready = snapshot.connectionState == ConnectionState.done;
      final allowed = ready && !snapshot.hasError && snapshot.data == null;
      final records = {
        for (final kind in reminderKinds)
          kind: ?widget.service?.saved(widget.race.id, kind),
      };
      final configuration = records.isEmpty
          ? '${tr(context, 'Race')} · ${tr(context, '1 hour before')}'
          : records.entries
                .map((entry) {
                  final minutes = entry.value['minutes'] as int;
                  final lead = minutes == 60
                      ? tr(context, '1 hour before')
                      : '$minutes ${tr(context, 'minutes before start')}';
                  return '${tr(context, entry.key)} · $lead';
                })
                .join(' / ');
      final status = records.isNotEmpty && allowed ? 'Enabled' : 'Not enabled';
      final permission = !ready
          ? 'Checking notification permission'
          : snapshot.hasError
          ? 'Notification permission unknown'
          : snapshot.data ?? 'Notifications allowed';
      return InkWell(
        key: const ValueKey('home-reminders'),
        onTap: () async {
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
          if (mounted) _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'Race reminders'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$configuration · ${tr(context, status)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      tr(context, permission),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      );
    },
  );
}
