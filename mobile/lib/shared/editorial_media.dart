import 'package:flutter/material.dart';

import '../core/language.dart';
import '../data/race_repository.dart';
import 'editorial.dart';
import 'presentation.dart';

/// Optional reviewed media; older APIs and missing assets retain the text layout.
class EditorialMediaView extends StatefulWidget {
  const EditorialMediaView({
    super.key,
    required this.repository,
    required this.raceId,
    required this.role,
    this.spoilerHidden = false,
    this.topic,
    this.compact = false,
    this.child,
    this.heroHeight = 280,
  });
  final Widget? child;
  final double heroHeight;
  final RaceRepository repository;
  final String raceId, role;
  final String? topic;
  final bool spoilerHidden, compact;
  @override
  State<EditorialMediaView> createState() => _EditorialMediaViewState();
}

class _EditorialMediaViewState extends State<EditorialMediaView> {
  late Future<List<EditorialMedia>> _media = widget.repository.media(
    widget.raceId,
  );
  @override
  void didUpdateWidget(covariant EditorialMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raceId != widget.raceId) {
      _media = widget.repository.media(widget.raceId);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<EditorialMedia>>(
    future: _media,
    builder: (context, snapshot) {
      final item = snapshot.data
          ?.where(
            (m) =>
                m.role == widget.role &&
                (widget.topic == null || m.topic == widget.topic) &&
                (!widget.spoilerHidden || !m.spoiler),
          )
          .firstOrNull;
      if (item == null) return widget.child ?? const SizedBox.shrink();
      if (widget.child != null) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -24,
              right: -24,
              top: 0,
              bottom: 0,
              child: Image.network(
                item.url,
                fit: BoxFit.cover,
                semanticLabel: item.caption,
                color: const Color(0xBBFFFFFF),
                colorBlendMode: BlendMode.modulate,
                errorBuilder: (_, error, stack) =>
                    Center(child: Text(tr(context, 'Media unavailable'))),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.heroHeight),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: widget.child,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: IconButton(
                tooltip: tr(context, 'Media credit'),
                icon: const Icon(Icons.info_outline, size: 18),
                onPressed: () => showEditorialDetail(
                  context,
                  title: tr(context, 'Media credit'),
                  body: '${item.caption}\n${item.credit}\n${item.license}',
                  sources: [
                    SourceReference(
                      publisher: item.credit,
                      url: item.sourceUrl,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      return EditorialMediaImage(item: item, compact: widget.compact);
    },
  );
}

class EditorialMediaImage extends StatelessWidget {
  const EditorialMediaImage({
    super.key,
    required this.item,
    this.compact = false,
  });
  final EditorialMedia item;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: item.credit,
        child: InkWell(
          onTap: () => showEditorialDetail(
            context,
            title: tr(context, 'Media credit'),
            body: '${item.caption}\n${item.credit}\n${item.license}',
            sources: [
              SourceReference(publisher: item.credit, url: item.sourceUrl),
            ],
          ),
          child: Image.network(
            item.url,
            fit: BoxFit.cover,
            semanticLabel: item.caption,
            errorBuilder: (_, error, stack) => Center(
              child: Icon(
                Icons.broken_image_outlined,
                semanticLabel: tr(context, 'Media unavailable'),
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: compact ? 1 : 1.6,
          child: Image.network(
            item.url,
            fit: BoxFit.cover,
            semanticLabel: item.caption,
            errorBuilder: (context, error, stack) =>
                Center(child: Text(tr(context, 'Media unavailable'))),
          ),
        ),
        TextButton(
          onPressed: () => showEditorialDetail(
            context,
            title: tr(context, 'Media credit'),
            body: '${item.caption}\n${item.credit}\n${item.license}',
            sources: [
              SourceReference(publisher: item.credit, url: item.sourceUrl),
            ],
          ),
          child: Text(
            item.credit,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
