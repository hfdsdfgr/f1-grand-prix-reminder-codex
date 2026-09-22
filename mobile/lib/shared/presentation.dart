import 'package:flutter/material.dart';

import '../core/language.dart';
import '../core/theme.dart';

class SectionHeading extends StatelessWidget {
  final String title;
  const SectionHeading(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
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
      SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
