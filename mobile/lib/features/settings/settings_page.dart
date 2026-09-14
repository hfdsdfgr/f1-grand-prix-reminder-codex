import 'package:flutter/material.dart';

import '../../core/language.dart';

class SettingsPage extends StatefulWidget {
  final bool spoilerFree;
  final ValueChanged<bool> onSpoilerFreeChanged;
  const SettingsPage({
    super.key,
    required this.spoilerFree,
    required this.onSpoilerFreeChanged,
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
            ],
          ),
        ),
      ),
    ),
  );
}
