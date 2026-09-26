import 'package:flutter/material.dart';

import '../core/language.dart';
import '../design/team_colors.dart';

enum TeamIdentitySize { compact, standard, label }

/// The marker supplements the readable name; it carries no interaction.
class TeamIdentity extends StatelessWidget {
  final String? teamId, teamName;
  final TeamIdentitySize size;
  const TeamIdentity({
    super.key,
    this.teamId,
    this.teamName,
    this.size = TeamIdentitySize.standard,
  });
  const TeamIdentity.compact({super.key, this.teamId, this.teamName})
    : size = TeamIdentitySize.compact;
  const TeamIdentity.label({super.key, this.teamId, this.teamName})
    : size = TeamIdentitySize.label;

  @override
  Widget build(BuildContext context) {
    final identity = teamVisualIdentity(teamId: teamId, teamName: teamName);
    final name = teamName?.trim().isNotEmpty == true
        ? teamName!.trim()
        : identity.displayName;
    final displayName = tr(context, name);
    final text = switch (size) {
      TeamIdentitySize.compact => identity.abbreviation,
      TeamIdentitySize.standard => '${identity.abbreviation}  $displayName',
      TeamIdentitySize.label => displayName,
    };
    return Semantics(
      label: '${identity.abbreviation}, $displayName',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 3,
              height: 18,
              child: ColoredBox(color: identity.color),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
