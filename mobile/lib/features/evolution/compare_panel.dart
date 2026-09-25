import 'package:flutter/material.dart';

import '../../core/language.dart';

class CompareChange {
  const CompareChange({
    required this.componentId,
    required this.component,
    required this.change,
    this.goal,
    this.expectedEffect,
    required this.status,
  });

  final String componentId, component, change, status;
  final String? goal, expectedEffect;
}

class EvolutionComparePanel extends StatelessWidget {
  const EvolutionComparePanel({
    super.key,
    required this.previous,
    required this.current,
    required this.changes,
    required this.ghostAvailable,
    required this.ghostEnabled,
    required this.onGhostChanged,
    required this.onComponentSelected,
  });

  final String previous, current;
  final List<CompareChange> changes;
  final bool ghostAvailable, ghostEnabled;
  final ValueChanged<bool> onGhostChanged;
  final ValueChanged<String> onComponentSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Side(label: tr(context, 'Previous'), value: previous),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _Side(label: tr(context, 'Current'), value: current),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        key: const ValueKey('ghost-compare'),
        contentPadding: EdgeInsets.zero,
        title: Text(tr(context, 'Ghost Compare')),
        subtitle: Text(
          tr(
            context,
            ghostAvailable
                ? 'Overlay the previous geometry over the current car.'
                : 'Two verified generation geometries are required.',
          ),
        ),
        value: ghostEnabled,
        onChanged: ghostAvailable ? onGhostChanged : null,
      ),
      if (changes.isEmpty)
        Text(
          tr(context, 'No sourced component differences are available.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      for (final change in changes)
        ListTile(
          key: ValueKey('compare-component-${change.componentId}'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.difference_outlined),
          title: Text(change.component),
          subtitle: Text(
            [
              change.change,
              if (change.goal != null) '${tr(context, 'Goal')}: ${change.goal}',
              if (change.expectedEffect != null)
                '${tr(context, 'Expected effect')}: ${change.expectedEffect}',
              '${tr(context, 'Status')}: ${tr(context, change.status)}',
            ].join('\n'),
          ),
          onTap: () => onComponentSelected(change.componentId),
        ),
    ],
  );
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}
