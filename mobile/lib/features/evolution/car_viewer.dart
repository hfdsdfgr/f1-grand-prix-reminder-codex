import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/language.dart';
import 'car_model.dart';
import 'gltf_car_stage.dart';

class CarViewer extends StatefulWidget {
  const CarViewer({super.key, this.enableGltf = true});

  final bool enableGltf;
  @override
  State<CarViewer> createState() => _CarViewerState();
}

class _CarViewerState extends State<CarViewer> {
  late Future<CarModel> _model = CarModel.load();
  final _focus = FocusNode();
  final _gltfController = GltfCarController();
  double _yaw = -.65, _pitch = .55, _zoom = 1, _startZoom = 1;
  String _selected = 'front_wing', _team = 'neutral', _archive = 'generic';
  bool _labels = true, _wire = false;
  bool _gltfReady = false, _gltfUnavailable = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _rotate(double dx, double dy) {
    _yaw = math.atan2(math.sin(_yaw + dx), math.cos(_yaw + dx));
    _pitch = (_pitch + dy).clamp(-80 * math.pi / 180, 89 * math.pi / 180);
  }

  void _view(double yaw, double pitch) => setState(() {
    _yaw = yaw;
    _pitch = pitch;
    _zoom = 1;
  });

  Future<void> _official(String value) async {
    final uri = Uri.tryParse(value);
    var opened = false;
    try {
      // URLs are reviewed build-time data; require HTTPS without tying the
      // reusable archive to one team's domain.
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // A missing browser must not break the offline explorer.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Unable to open the official page.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CarModel>(
    future: _model,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Unable to load the car model.')),
            TextButton(
              onPressed: () => setState(() => _model = CarModel.load()),
              child: Text(tr(context, 'Retry')),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return SizedBox(
          height: 390,
          child: Center(
            child: CircularProgressIndicator(
              semanticsLabel: tr(context, 'Loading car model'),
            ),
          ),
        );
      }
      final model = snapshot.data!,
          zh = Localizations.localeOf(context).languageCode == 'zh';
      final component = model.components.firstWhere((c) => c.id == _selected),
          text = component.text(zh);
      final archives = model.archives.where((c) => c['team'] == _team).toList();
      final matches = archives.where((c) => c['car_model_id'] == _archive);
      final archive = matches.isEmpty ? null : matches.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Explore the car'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(tr(context, 'Generic model — not a team specification.')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final team in const {
                'neutral': 'Generic model',
                'ferrari': 'Ferrari',
                'mclaren': 'McLaren',
                'mercedes': 'Mercedes',
                'redbull': 'Red Bull',
              }.entries)
                ChoiceChip(
                  label: Text(tr(context, team.value)),
                  selected: _team == team.key,
                  onSelected: (_) => setState(() {
                    _team = team.key;
                    _archive = 'generic';
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('archive-$_team-$_archive'),
            initialValue: _archive,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(context, 'Car archive')),
            items: [
              DropdownMenuItem(
                value: 'generic',
                child: Text(tr(context, 'Generic illustration')),
              ),
              for (final car in archives)
                DropdownMenuItem(
                  value: car['car_model_id'] as String,
                  child: Text('${car['season']} / ${car['name']}'),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _archive = value);
            },
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              archive == null
                  ? 'Team-inspired colours only; not an official livery.'
                  : 'Identity verified; generation geometry unavailable. Showing the generic illustration.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (archive?['official_url'] != null)
            TextButton.icon(
              onPressed: () => _official(archive!['official_url'] as String),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(tr(context, 'Official Car')),
            ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(
                constraints.maxWidth,
                constraints.maxWidth < 500 ? 390 : 480,
              );
              final painter = CarPainter(
                model: model,
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom,
                selected: _selected,
                team: _team,
                labels: _labels,
                wire: _wire,
                scheme: Theme.of(context).colorScheme,
                chinese: zh,
                textScaler: MediaQuery.textScalerOf(context),
                renderModel: !_gltfReady || _wire,
              );
              return Semantics(
                label: tr(context, 'Interactive car model'),
                value: text[0],
                child: Focus(
                  focusNode: _focus,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    final key = event.logicalKey;
                    if (![
                      LogicalKeyboardKey.arrowLeft,
                      LogicalKeyboardKey.arrowRight,
                      LogicalKeyboardKey.arrowUp,
                      LogicalKeyboardKey.arrowDown,
                      LogicalKeyboardKey.equal,
                      LogicalKeyboardKey.add,
                      LogicalKeyboardKey.minus,
                    ].contains(key)) {
                      return KeyEventResult.ignored;
                    }
                    setState(() {
                      if (key == LogicalKeyboardKey.arrowLeft) _rotate(-.1, 0);
                      if (key == LogicalKeyboardKey.arrowRight) _rotate(.1, 0);
                      if (key == LogicalKeyboardKey.arrowUp) _rotate(0, .1);
                      if (key == LogicalKeyboardKey.arrowDown) _rotate(0, -.1);
                      if (key == LogicalKeyboardKey.equal ||
                          key == LogicalKeyboardKey.add) {
                        _zoom = (_zoom + .1).clamp(.5, 3);
                      }
                      if (key == LogicalKeyboardKey.minus) {
                        _zoom = (_zoom - .1).clamp(.5, 3);
                      }
                    });
                    return KeyEventResult.handled;
                  },
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        GestureBinding.instance.pointerSignalResolver.register(
                          event,
                          (_) => setState(
                            () => _zoom =
                                (_zoom * math.exp(-event.scrollDelta.dy * .001))
                                    .clamp(.5, 3),
                          ),
                        );
                      }
                    },
                    child: GestureDetector(
                      key: const ValueKey('car-gesture'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (_) {
                        _focus.requestFocus();
                        _startZoom = _zoom;
                      },
                      onScaleUpdate: (d) => setState(() {
                        if (d.pointerCount > 1) {
                          _zoom = (_startZoom * d.scale).clamp(.5, 3);
                        } else {
                          _rotate(
                            d.focalPointDelta.dx * .01,
                            d.focalPointDelta.dy * .01,
                          );
                        }
                      }),
                      onTapUp: (d) {
                        _focus.requestFocus();
                        final hit = _gltfReady
                            ? _gltfController.partAt(d.localPosition, size)
                            : painter.partAt(d.localPosition, size);
                        if (hit != null) setState(() => _selected = hit);
                      },
                      child: RepaintBoundary(
                        child: SizedBox.fromSize(
                          size: size,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (widget.enableGltf && !_gltfUnavailable)
                                GltfCarStage(
                                  model: model,
                                  controller: _gltfController,
                                  yaw: _yaw,
                                  pitch: _pitch,
                                  zoom: _zoom,
                                  selected: _selected,
                                  team: _team,
                                  onReady: () {
                                    if (mounted && !_gltfReady) {
                                      setState(() => _gltfReady = true);
                                    }
                                  },
                                  onUnavailable: () {
                                    if (mounted && !_gltfUnavailable) {
                                      setState(() {
                                        _gltfReady = false;
                                        _gltfUnavailable = true;
                                      });
                                    }
                                  },
                                ),
                              CustomPaint(
                                key: const ValueKey('car-canvas'),
                                painter: painter,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Text(
            tr(context, 'Drag to rotate · Pinch to zoom'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 4,
            children: [
              for (final view in [
                ('Reset view', -.65, .55),
                ('Front view', math.pi, .12),
                ('Side view', math.pi / 2, .12),
                ('Top view', 0.0, math.pi / 2 - .01),
                ('Rear view', 0.0, .12),
              ])
                TextButton(
                  onPressed: () => _view(view.$2, view.$3),
                  child: Text(tr(context, view.$1)),
                ),
              IconButton(
                tooltip: tr(context, 'Rotate left'),
                onPressed: () => setState(() => _rotate(-.1, 0)),
                icon: const Icon(Icons.rotate_left),
              ),
              IconButton(
                tooltip: tr(context, 'Rotate right'),
                onPressed: () => setState(() => _rotate(.1, 0)),
                icon: const Icon(Icons.rotate_right),
              ),
              IconButton(
                tooltip: tr(context, 'Zoom in'),
                onPressed: () =>
                    setState(() => _zoom = (_zoom + .1).clamp(.5, 3)),
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                tooltip: tr(context, 'Zoom out'),
                onPressed: () =>
                    setState(() => _zoom = (_zoom - .1).clamp(.5, 3)),
                icon: const Icon(Icons.zoom_out),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('component-$_selected'),
            initialValue: _selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr(context, 'Car component'),
            ),
            items: [
              for (final c in model.components)
                DropdownMenuItem(value: c.id, child: Text(c.text(zh)[0])),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selected = value);
            },
          ),
          const SizedBox(height: 8),
          Text(component.id, style: Theme.of(context).textTheme.bodySmall),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      context,
                      [
                        'What is it?',
                        'What does it do?',
                        'Why does it matter?',
                      ][i],
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(text[i + 1]),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            tr(
              context,
              'Static draft awaiting human review. Current specification and upgrades: unavailable.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'Component labels')),
            value: _labels,
            onChanged: (v) => setState(() => _labels = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'Wireframe')),
            value: _wire,
            onChanged: (v) => setState(() => _wire = v),
          ),
        ],
      );
    },
  );
}

class _Face {
  final String part;
  final Path path;
  final double depth;
  final CarFace source;
  _Face(this.part, this.path, this.depth, this.source);
}

// ponytail: face sorting matches the approved prototype; transparent comparison
// needs a depth-buffer renderer, not more sorting heuristics.
class CarPainter extends CustomPainter {
  final CarModel model;
  final double yaw, pitch, zoom;
  final String selected, team;
  final bool labels, wire, chinese;
  final bool renderModel;
  final ColorScheme scheme;
  final TextScaler textScaler;
  Size? _cachedSize;
  List<_Face> _cachedFaces = [];
  CarPainter({
    required this.model,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.selected,
    required this.team,
    required this.labels,
    required this.wire,
    required this.chinese,
    required this.scheme,
    required this.textScaler,
    this.renderModel = true,
  });

  (Offset, double) _project(CarPoint p, Size size) {
    final x = p.$1, y = p.$2 - .45, z = p.$3;
    final rx = x * math.cos(yaw) + z * math.sin(yaw),
        rz = z * math.cos(yaw) - x * math.sin(yaw);
    final ry = y * math.cos(pitch) - rz * math.sin(pitch),
        depth = y * math.sin(pitch) + rz * math.cos(pitch);
    final scale = math.min(size.width / 6, size.height / 5) * zoom;
    return (
      Offset(size.width / 2 + rx * scale, size.height / 2 - ry * scale),
      depth,
    );
  }

  List<_Face> _faces(Size size) {
    if (_cachedSize == size) return _cachedFaces;
    _cachedSize = size;
    _cachedFaces = [
      for (final c in model.components)
        for (final f in c.faces) _makeFace(c.id, f, size),
    ];
    _cachedFaces.sort((a, b) => a.depth.compareTo(b.depth));
    return _cachedFaces;
  }

  _Face _makeFace(String id, CarFace face, Size size) {
    final points = face.points.map((p) => _project(p, size)).toList();
    return _Face(
      id,
      Path()..addPolygon(points.map((p) => p.$1).toList(), true),
      points.fold(0.0, (s, p) => s + p.$2) / points.length,
      face,
    );
  }

  String? partAt(Offset point, Size size) {
    for (final face in _faces(size).reversed) {
      if (face.path.contains(point)) return face.part;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (renderModel) {
      for (final f in _faces(size)) {
        final active = f.part == selected;
        final base = active
            ? scheme.primary
            : switch (f.source.material) {
                'tyre' => const Color(0xff303338),
                'hub' => const Color(0xff707980),
                _ => model.materials[team]![f.source.material]!,
              };
        var color = Color.from(
          alpha: 1,
          red: base.r * f.source.light,
          green: base.g * f.source.light,
          blue: base.b * f.source.light,
        );
        if (!active) color = Color.lerp(color, scheme.surface, .18)!;
        if (!wire) canvas.drawPath(f.path, Paint()..color = color);
        canvas.drawPath(
          f.path,
          Paint()
            ..color = (wire
                ? active
                      ? scheme.primary
                      : scheme.outline
                : color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (wire ? 0.6 : 0.45),
        );
      }
    }
    if (labels) _paintLabels(canvas, size);
    canvas.restore();
  }

  void _paintLabels(Canvas canvas, Size size) {
    final ids = {
      selected,
      'front_wing',
      'rear_wing',
      'sidepods',
      'halo',
      'floor',
      'front_wheels',
    };
    final anchors = <({CarComponent component, Offset point})>[];
    for (final id in ids) {
      final c = model.components.firstWhere((c) => c.id == id),
          p = _project(c.anchor, size).$1;
      if (p.dx > 8 &&
          p.dx < size.width - 8 &&
          p.dy > 40 &&
          p.dy < size.height - 25) {
        anchors.add((component: c, point: p));
      }
      if (anchors.length >= (size.width < 500 ? 3 : 6)) break;
    }
    final fontSize = textScaler.scale(12), gap = math.max(32.0, fontSize + 12);
    for (final left in [true, false]) {
      final list =
          anchors.where((a) => (a.point.dx < size.width / 2) == left).toList()
            ..sort((a, b) => a.point.dy.compareTo(b.point.dy));
      var previous = 40 + fontSize;
      for (var i = 0; i < list.length; i++) {
        final a = list[i],
            color = a.component.id == selected
                ? scheme.primary
                : scheme.onSurfaceVariant;
        final text = TextPainter(
          text: TextSpan(
            text: a.component.text(chinese)[0],
            style: TextStyle(color: color, fontSize: fontSize),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: math.max(40, size.width * .34));
        final maxY = size.height - 28 - (list.length - 1 - i) * gap;
        if (maxY < previous) continue;
        final y = a.point.dy.clamp(previous, maxY),
            x = left ? 12.0 : size.width - 12 - text.width;
        previous = y + gap;
        final edge = left ? x + text.width + 6 : x - 6;
        canvas.drawPath(
          Path()
            ..moveTo(a.point.dx, a.point.dy)
            ..lineTo(edge + (left ? 12 : -12), y - text.height / 2)
            ..lineTo(edge, y - text.height / 2),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = .75,
        );
        final offset = Offset(x, y - text.height);
        canvas.drawRect(
          Rect.fromLTWH(x - 4, offset.dy - 2, text.width + 8, text.height + 4),
          Paint()..color = scheme.surface,
        );
        text.paint(canvas, offset);
        canvas.drawCircle(a.point, 2, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CarPainter old) =>
      model != old.model ||
      yaw != old.yaw ||
      pitch != old.pitch ||
      zoom != old.zoom ||
      selected != old.selected ||
      team != old.team ||
      labels != old.labels ||
      wire != old.wire ||
      renderModel != old.renderModel ||
      chinese != old.chinese ||
      scheme != old.scheme ||
      textScaler != old.textScaler;
}
