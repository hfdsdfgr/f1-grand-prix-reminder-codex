import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/language.dart';
import '../core/theme.dart';

class SectionHeading extends StatelessWidget {
  final String title;
  const SectionHeading(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: RaceSpace.medium),
      const Divider(),
      const SizedBox(height: RaceSpace.medium),
    ],
  );
}

class ContentState extends StatelessWidget {
  final String message;
  final bool loading;
  final String? detail;
  final VoidCallback? onRetry;
  const ContentState(
    this.message, {
    super.key,
    this.loading = false,
    this.onRetry,
    this.detail,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: RaceSpace.large),
    child: Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading) ...[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(semanticsLabel: message),
            ),
            const SizedBox(height: RaceSpace.small),
          ],
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          if (detail != null)
            Text(detail!, style: Theme.of(context).textTheme.bodySmall),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'Retry')),
            ),
        ],
      ),
    ),
  );
}

class SourceReference extends StatelessWidget {
  final String? publisher;
  final String url;
  const SourceReference({super.key, this.publisher, required this.url});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (publisher != null && publisher!.isNotEmpty)
        Text(publisher!, style: Theme.of(context).textTheme.titleSmall),
      Row(
        children: [
          Expanded(
            child: SelectableText(
              url,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: tr(context, 'Open source'),
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: () async {
              final uri = Uri.tryParse(url);
              var opened = false;
              try {
                if (uri != null &&
                    ['https', 'http'].contains(uri.scheme) &&
                    uri.host.isNotEmpty) {
                  opened = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                }
              } catch (_) {
                /* The source remains selectable when no browser is installed. */
              }
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr(context, 'Unable to open source.')),
                  ),
                );
              }
            },
          ),
        ],
      ),
    ],
  );
}
