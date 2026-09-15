import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../data/follow_service.dart';

class SettingsPage extends StatefulWidget {
  final bool spoilerFree;
  final ValueChanged<bool> onSpoilerFreeChanged;
  final FollowService? follows;
  const SettingsPage({
    super.key,
    required this.spoilerFree,
    required this.onSpoilerFreeChanged,
    this.follows,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _spoilerFree = widget.spoilerFree;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Settings'))),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'Spoiler-free mode')),
                subtitle: Text(
                  tr(
                    context,
                    'Hide completed-session results until you reveal them.',
                  ),
                ),
                value: _spoilerFree,
                onChanged: (value) {
                  setState(() => _spoilerFree = value);
                  widget.onSpoilerFreeChanged(value);
                },
              ),
              if (widget.follows case final follows?) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: follows,
                  builder: (context, _) => _FollowSettings(follows: follows),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _FollowSettings extends StatelessWidget {
  final FollowService follows;
  const _FollowSettings({required this.follows});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        tr(context, 'Following'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(tr(context, 'Choose drivers and teams from race results.')),
      const SizedBox(height: 24),
      _FollowList(
        title: 'Followed drivers',
        entries: follows.drivers,
        onRemove: follows.toggleDriver,
      ),
      const SizedBox(height: 24),
      _FollowList(
        title: 'Followed teams',
        entries: follows.teams,
        onRemove: follows.toggleTeam,
      ),
    ],
  );
}

class _FollowList extends StatelessWidget {
  final String title;
  final List<FollowEntry> entries;
  final Future<void> Function(String, String) onRemove;
  const _FollowList({
    required this.title,
    required this.entries,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(tr(context, title), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (entries.isEmpty)
        Text(
          tr(
            context,
            title == 'Followed drivers'
                ? 'No drivers followed yet.'
                : 'No teams followed yet.',
          ),
        )
      else
        for (final entry in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.name),
            trailing: IconButton(
              tooltip: tr(context, 'Unfollow'),
              onPressed: () => onRemove(entry.id, entry.name),
              icon: const Icon(Icons.star),
            ),
          ),
    ],
  );
}
