import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

typedef CarPoint = (double, double, double);
CarPoint _point(List<dynamic> v) => (
  (v[0] as num).toDouble(),
  (v[1] as num).toDouble(),
  (v[2] as num).toDouble(),
);

class CarFace {
  final List<CarPoint> points;
  final String material;
  late final double light = _lighting();
  CarFace(Map<String, dynamic> json)
    : points = (json['points'] as List).map((p) => _point(p)).toList(),
      material = json['material'];
  double _lighting() {
    final a = points[0], b = points[1], c = points[2];
    final ux = b.$1 - a.$1,
        uy = b.$2 - a.$2,
        uz = b.$3 - a.$3,
        vx = c.$1 - a.$1,
        vy = c.$2 - a.$2,
        vz = c.$3 - a.$3;
    final nx = uy * vz - uz * vy,
        ny = uz * vx - ux * vz,
        nz = ux * vy - uy * vx;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    return .64 +
        .32 *
            ((nx * .35 + ny * .85 + nz * .4) / (length == 0 ? 1 : length))
                .abs();
  }
}

class CarComponent {
  final String id;
  final CarPoint anchor;
  final List<String> chinese, english;
  final List<CarFace> faces;
  CarComponent(Map<String, dynamic> json)
    : id = json['id'],
      anchor = _point(json['anchor']),
      chinese = [json['name'], json['what'], json['does'], json['why']],
      english = List<String>.from(json['en']),
      faces = (json['faces'] as List).map((f) => CarFace(f)).toList();
  List<String> text(bool zh) => zh ? chinese : english;
}

class CarModel {
  final List<CarComponent> components;
  final Map<String, Map<String, Color>> materials;
  final List<Map<String, dynamic>> archives;
  CarModel(Map<String, dynamic> json)
    : components = (json['components'] as List)
          .map((c) => CarComponent(c))
          .toList(),
      materials = (json['materials'] as Map<String, dynamic>).map(
        (team, colors) => MapEntry(
          team,
          (colors as Map<String, dynamic>).map(
            (key, value) => MapEntry(
              key,
              Color(
                int.parse((value as String).replaceFirst('#', 'ff'), radix: 16),
              ),
            ),
          ),
        ),
      ),
      archives = (json['carModels'] as List).cast<Map<String, dynamic>>();
  static Future<CarModel> load() async => CarModel(
    jsonDecode(await rootBundle.loadString('assets/evolution/car.json'))
        as Map<String, dynamic>,
  );
}
