import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../data/race_repository.dart';
import '../../shared/editorial.dart';
import '../../shared/team_identity.dart';
import '../../shared/presentation.dart';
import 'car_model.dart';
import 'car_viewer.dart';

class ComponentThumbnail extends StatelessWidget {
  const ComponentThumbnail({
    super.key,
    required this.componentId,
    required this.teamId,
  });
  final String componentId, teamId;
  static final _model = CarModel.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<CarModel>(
    future: _model,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const SizedBox.shrink();
      return ExcludeSemantics(
        child: CustomPaint(
          painter: CarPainter(
            model: snapshot.data!,
            yaw: -.65,
            pitch: .55,
            zoom: 1,
            selected: componentId,
            team: carTeamKey(teamId),
            labels: false,
            wire: false,
            chinese: false,
            scheme: Theme.of(context).colorScheme,
            textScaler: TextScaler.noScaling,
            focus: 0,
            exploded: 0,
            technical: true,
            isolated: true,
          ),
        ),
      );
    },
  );
}

class ComponentExplorer extends StatefulWidget {
  const ComponentExplorer({
    super.key,
    required this.entries,
    required this.initialId,
    this.enableGltf = true,
    this.stale = false,
  });
  final List<UpgradeEntry> entries;
  final String initialId;
  final bool enableGltf, stale;
  @override
  State<ComponentExplorer> createState() => _ComponentExplorerState();
}

class _ComponentExplorerState extends State<ComponentExplorer> {
  late String _id = widget.initialId;
  @override
  Widget build(BuildContext context) {
    final entry = widget.entries.firstWhere((e) => e.id == _id);
    final mapped = carComponentIds.contains(entry.componentId);
    final confidence = double.tryParse(entry.confidence);
    final validConfidence =
        confidence != null &&
        confidence.isFinite &&
        confidence >= 0 &&
        confidence <= 1;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: RaceSpace.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorialHeader(
                title: entry.component,
                trailing: EditorialShare(
                  title: entry.title,
                  sources: entry.sources.map((s) => s.url).toList(),
                ),
                eyebrow: [
                  if (entry.round != null) '${entry.round}',
                  tr(context, entry.race ?? 'Unknown'),
                ].join(' / '),
              ),
              TeamIdentity(teamId: entry.teamId, teamName: entry.team),
              if (widget.stale)
                ContentState(
                  tr(context, 'Showing saved upgrades. They may have changed.'),
                ),
              if (mapped)
                CarViewer(
                  key: ValueKey(entry.id),
                  editorial: true,
                  initialFocus: true,
                  componentOnly: true,
                  enableGltf: widget.enableGltf,
                  highlightedComponentId: entry.componentId,
                  highlightedTeamId: carTeamKey(entry.teamId, entry.team),
                  showTeamSelector: false,
                )
              else
                ContentState(
                  tr(
                    context,
                    'This upgrade has no compatible 3D component mapping.',
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.entries.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = widget.entries[index];
                    return Semantics(
                      selected: item.id == _id,
                      button: true,
                      label:
                          '${item.team} · ${tr(context, item.component)} · ${tr(context, item.status)}',
                      child: Tooltip(
                        message:
                            '${item.team} · ${tr(context, item.component)}',
                        child: InkWell(
                          onTap: () => setState(() => _id = item.id),
                          child: Container(
                            width: 96,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: item.id == _id
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                              ),
                            ),
                            child: carComponentIds.contains(item.componentId)
                                ? ComponentThumbnail(
                                    componentId: item.componentId!,
                                    teamId: item.teamId,
                                  )
                                : Center(
                                    child: Text(tr(context, item.component)),
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              EditorialLabel(
                '${tr(context, entry.team)} · ${tr(context, entry.status)}',
              ),
              const SizedBox(height: 8),
              Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
              EvidenceField('Details', entry.change),
              EvidenceField('Purpose', entry.goal),
              if (entry.expectedEffect != null)
                EvidenceField('Expected effect', entry.expectedEffect),
              EvidenceField(
                'Confidence',
                validConfidence
                    ? '${confidence < .75 ? '${tr(context, 'Low')} · ' : ''}${confidence.toString()}'
                    : tr(context, 'Unknown'),
              ),
              Text(
                tr(context, 'Review original evidence.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              const EditorialLabel('Sources', accent: true),
              for (final source in entry.sources)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SourceReference(
                        publisher: source.provider,
                        url: source.url,
                      ),
                      if (source.publishedAt != null)
                        Text(
                          MaterialLocalizations.of(context)
                              .formatMediumDate(source.publishedAt!),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
