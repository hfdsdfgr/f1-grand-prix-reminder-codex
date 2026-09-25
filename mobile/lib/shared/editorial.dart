import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/language.dart';
import '../core/theme.dart';
import 'presentation.dart';

class EditorialShare extends StatelessWidget {
  const EditorialShare({super.key, required this.title, required this.sources});
  final String title;
  final List<String> sources;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tr(context, 'Share'),
    icon: const Icon(Icons.ios_share, size: 20),
    onPressed: () async {
      final box = context.findRenderObject() as RenderBox?;
      try {
        final result = await SharePlus.instance.share(
          ShareParams(
            title: title,
            text: [title, ...sources.toSet()].join('\n'),
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
        if (result.status == ShareResultStatus.unavailable && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'Sharing is unavailable.'))),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr(context, 'Unable to share. Please try again.')),
            ),
          );
        }
      }
    },
  );
}

/// The shared visual grammar; domain data and navigation stay with the caller.
class EditorialHeader extends StatelessWidget {
  const EditorialHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? eyebrow, subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: EditorialLabel(eyebrow!),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              tr(context, title).toUpperCase(),
              style: Theme.of(context).textTheme.displaySmall,
            ),
          ),
          ?trailing,
        ],
      ),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 16),
          child: Text(
            tr(context, subtitle!),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w400),
          ),
        ),
    ],
  );
}

class EditorialLabel extends StatelessWidget {
  const EditorialLabel(this.text, {super.key, this.accent = false});
  final String text;
  final bool accent;
  @override
  Widget build(BuildContext context) => Text(
    tr(context, text).toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      letterSpacing: .8,
      color: accent
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class EditorialTabs extends StatelessWidget {
  const EditorialTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Semantics(
                selected: selected == i,
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 64,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: i == selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: EditorialLabel(labels[i], accent: i == selected),
                  ),
                ),
              ),
          ],
        ),
      ),
      const Divider(),
    ],
  );
}

class EditorialRow extends StatelessWidget {
  const EditorialRow({
    super.key,
    required this.title,
    this.number,
    this.selected = false,
    this.subtitle,
    this.detail,
    this.thumbnail,
    required this.onTap,
  });
  final String title;
  final String? subtitle, detail;
  final int? number;
  final bool selected;
  final Widget? thumbnail;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (number != null)
                  SizedBox(
                    width: 42,
                    child: Text(
                      number.toString().padLeft(2, '0'),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EditorialLabel(title, accent: true),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      if (detail != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            detail!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
                if (thumbnail != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: SizedBox(width: 72, height: 76, child: thumbnail),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
      ],
    ),
  );
}

class EvidenceField extends StatelessWidget {
  const EvidenceField(this.label, this.value, {super.key});
  final String label;
  final String? value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorialLabel(label, accent: true),
        const SizedBox(height: 8),
        SelectableText(
          value?.trim().isNotEmpty == true ? value! : tr(context, 'Unknown'),
        ),
        const SizedBox(height: 16),
        const Divider(),
      ],
    ),
  );
}

Future<void> showEditorialDetail(
  BuildContext context, {
  required String title,
  required String body,
  required List<Widget> sources,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: RaceSpace.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorialHeader(title: title),
              const SizedBox(height: 24),
              SelectableText(body),
              const SizedBox(height: 32),
              SectionHeading(tr(context, 'Sources')),
              ...sources,
            ],
          ),
        ),
      ),
    ),
  ),
);
