import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/language.dart';

// Generic geometry only: coordinates do not describe any team's real car.
const _parts = [
  ('Front Wing', 0.0, 0.18, -2.35, 2.0, 0.12, 0.45),
  ('Nose', 0.0, 0.42, -1.5, 0.35, 0.3, 1.35),
  ('Front Suspension', 0.0, 0.4, -1.35, 1.65, 0.08, 0.25),
  ('Front Tyres', -0.95, 0.42, -1.35, 0.42, 0.8, 0.75),
  ('Front Tyres', 0.95, 0.42, -1.35, 0.42, 0.8, 0.75),
  ('Sidepods', -0.48, 0.48, 0.2, 0.5, 0.4, 1.45),
  ('Sidepods', 0.48, 0.48, 0.2, 0.5, 0.4, 1.45),
  ('Floor', 0.0, 0.16, 0.25, 1.65, 0.08, 2.55),
  ('Engine Cover', 0.0, 0.75, 0.7, 0.42, 0.6, 1.2),
  ('Power Unit', 0.0, 0.42, 0.9, 0.5, 0.35, 0.65),
  ('Rear Suspension', 0.0, 0.4, 1.55, 1.65, 0.08, 0.25),
  ('Rear Tyres', -0.95, 0.45, 1.55, 0.5, 0.85, 0.85),
  ('Rear Tyres', 0.95, 0.45, 1.55, 0.5, 0.85, 0.85),
  ('Beam Wing', 0.0, 0.5, 2.0, 1.25, 0.1, 0.3),
  ('Rear Wing', 0.0, 1.1, 2.0, 1.6, 0.16, 0.5),
];

class CarViewer extends StatefulWidget {
  const CarViewer({super.key});

  @override
  State<CarViewer> createState() => _CarViewerState();
}

class _CarViewerState extends State<CarViewer> {
  double _yaw = -0.65, _pitch = 0.55, _zoom = 1, _startZoom = 1;
  String _selected = 'Front Wing';
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'Explore the car'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(tr(context, 'Generic model — not a team specification.')),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, 280);
            final painter = _CarPainter(
              yaw: _yaw,
              pitch: _pitch,
              zoom: _zoom,
              selected: _selected,
              focused: _focused,
              scheme: scheme,
              label: tr(context, _selected),
            );
            return Semantics(
              label: tr(context, 'Interactive car model'),
              value: tr(context, _selected),
              child: GestureDetector(
                onScaleStart: (_) => _startZoom = _zoom,
                onScaleUpdate: (details) => setState(() {
                  _zoom = (_startZoom * details.scale).clamp(0.6, 2.5);
                  if (details.pointerCount == 1) {
                    _yaw += details.focalPointDelta.dx * 0.01;
                    _pitch = (_pitch + details.focalPointDelta.dy * 0.01).clamp(
                      -0.8,
                      1.4,
                    );
                  }
                }),
                onTapUp: (details) {
                  final hit = painter.partAt(details.localPosition, size);
                  if (hit != null) setState(() => _selected = hit);
                },
                child: RepaintBoundary(
                  child: CustomPaint(size: size, painter: painter),
                ),
              ),
            );
          },
        ),
        Text(tr(context, 'Drag to rotate · Pinch to zoom')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(_selected),
          initialValue: _selected,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr(context, 'Car component')),
          items: [
            for (final name in _parts.map((p) => p.$1).toSet())
              DropdownMenuItem(value: name, child: Text(tr(context, name))),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _selected = value);
          },
        ),
        Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: tr(context, 'Rotate left'),
              onPressed: () => setState(() => _yaw -= 0.3),
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton(
              tooltip: tr(context, 'Rotate right'),
              onPressed: () => setState(() => _yaw += 0.3),
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton(
              tooltip: tr(context, 'Zoom in'),
              onPressed: () =>
                  setState(() => _zoom = (_zoom + 0.2).clamp(0.6, 2.5)),
              icon: const Icon(Icons.zoom_in),
            ),
            IconButton(
              tooltip: tr(context, 'Zoom out'),
              onPressed: () =>
                  setState(() => _zoom = (_zoom - 0.2).clamp(0.6, 2.5)),
              icon: const Icon(Icons.zoom_out),
            ),
            TextButton(
              onPressed: () => setState(() => _focused = !_focused),
              child: Text(
                tr(context, _focused ? 'Show whole car' : 'Focus component'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _yaw = -0.65;
                _pitch = 0.55;
                _zoom = 1;
                _focused = false;
              }),
              child: Text(tr(context, 'Reset view')),
            ),
          ],
        ),
        if (_selected == 'Power Unit')
          Text(tr(context, 'Internal component: use focus to inspect.')),
      ],
    );
  }
}

class _Face {
  final String part;
  final Path path;
  final double depth;
  final int side;
  const _Face(this.part, this.path, this.depth, this.side);
}

class _CarPainter extends CustomPainter {
  final double yaw, pitch, zoom;
  final String selected, label;
  final bool focused;
  final ColorScheme scheme;
  const _CarPainter({
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.selected,
    required this.focused,
    required this.scheme,
    required this.label,
  });

  (Offset, double) _project(double x, double y, double z, Size size) {
    if (focused) {
      final part = _parts.firstWhere((p) => p.$1 == selected);
      // Paired components focus together around the centreline.
      y -= part.$3;
      z -= part.$4;
    } else {
      y -= 0.45;
    }
    final rx = x * math.cos(yaw) + z * math.sin(yaw);
    final rz = z * math.cos(yaw) - x * math.sin(yaw);
    final ry = y * math.cos(pitch) - rz * math.sin(pitch);
    final depth = y * math.sin(pitch) + rz * math.cos(pitch);
    final scale = math.min(size.width / 6, size.height / 5) * zoom;
    return (
      Offset(size.width / 2 + rx * scale, size.height / 2 - ry * scale),
      depth,
    );
  }

  List<_Face> _faces(Size size) {
    final faces = <_Face>[];
    for (final p in _parts) {
      if (focused && p.$1 != selected) continue;
      final points = [
        for (final z in [-1, 1])
          for (final y in [-1, 1])
            for (final x in [-1, 1])
              _project(
                p.$2 + x * p.$5 / 2,
                p.$3 + y * p.$6 / 2,
                p.$4 + z * p.$7 / 2,
                size,
              ),
      ];
      const indices = [
        [0, 1, 3, 2],
        [4, 6, 7, 5],
        [0, 4, 5, 1],
        [2, 3, 7, 6],
        [0, 2, 6, 4],
        [1, 5, 7, 3],
      ];
      for (var side = 0; side < indices.length; side++) {
        final ids = indices[side];
        final path = Path()
          ..addPolygon([for (final i in ids) points[i].$1], true);
        faces.add(
          _Face(
            p.$1,
            path,
            ids.fold(0.0, (sum, i) => sum + points[i].$2) / 4,
            side,
          ),
        );
      }
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    return faces;
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
    for (final face in _faces(size)) {
      final color = face.part == selected
          ? scheme.primary
          : face.part.contains('Tyres')
          ? scheme.outline
          : scheme.surfaceContainerHighest;
      canvas.drawPath(
        face.path,
        Paint()
          ..color = Color.lerp(color, scheme.onSurface, face.side * 0.035)!,
      );
      canvas.drawPath(
        face.path,
        Paint()
          ..color = scheme.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
    }
    final p = _parts.firstWhere((p) => p.$1 == selected);
    final anchor = _project(p.$2, p.$3, p.$4, size).$1;
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: scheme.onSurface, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 24);
    final labelPosition = Offset(12, size.height - text.height - 12);
    canvas.drawLine(anchor, labelPosition, Paint()..color = scheme.primary);
    canvas.drawCircle(anchor, 3, Paint()..color = scheme.primary);
    canvas.drawRect(
      Rect.fromLTWH(
        labelPosition.dx - 4,
        labelPosition.dy - 2,
        text.width + 8,
        text.height + 4,
      ),
      Paint()..color = scheme.surface,
    );
    text.paint(canvas, labelPosition);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CarPainter oldDelegate) =>
      yaw != oldDelegate.yaw ||
      pitch != oldDelegate.pitch ||
      zoom != oldDelegate.zoom ||
      selected != oldDelegate.selected ||
      focused != oldDelegate.focused ||
      scheme != oldDelegate.scheme ||
      label != oldDelegate.label;
}
