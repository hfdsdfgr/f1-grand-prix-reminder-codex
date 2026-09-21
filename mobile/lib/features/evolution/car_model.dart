import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

typedef CarPoint = (double, double, double);

const carComponentIds = {
  'front_wing',
  'nose',
  'front_suspension',
  'front_wheels',
  'halo',
  'cockpit',
  'sidepods',
  'floor',
  'engine_cover',
  'rear_suspension',
  'rear_wheels',
  'beam_wing',
  'rear_wing',
};
const _paletteMaterialIds = {'body', 'secondary', 'carbon', 'accent'};
const _meshMaterialIds = {..._paletteMaterialIds, 'tyre', 'hub'};

CarPoint carPartOffset(String id) => switch (id) {
  'front_wing' => (0, 0, -.72),
  'nose' => (0, .08, -.32),
  'front_suspension' => (-.28, .08, -.22),
  'front_wheels' => (-.52, .04, -.18),
  'halo' => (0, .48, 0),
  'cockpit' => (0, .26, 0),
  'sidepods' => (.42, .04, 0),
  'floor' => (0, -.42, 0),
  'engine_cover' => (-.34, .24, .15),
  'rear_suspension' => (.28, .08, .22),
  'rear_wheels' => (.52, .04, .18),
  'beam_wing' => (0, .08, .48),
  'rear_wing' => (0, .34, .68),
  _ => (0, 0, 0),
};

String carTeamKey(String? teamId) => switch (teamId) {
  'ferrari' => 'ferrari',
  'mclaren' => 'mclaren',
  'mercedes' => 'mercedes',
  'red_bull' || 'redbull' => 'redbull',
  _ => 'neutral',
};
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
  CarModel._(this.components, this.materials, this.archives);

  factory CarModel(Map<String, dynamic> json) {
    final components = (json['components'] as List)
        .map((c) => CarComponent(c))
        .toList();
    final materials = (json['materials'] as Map<String, dynamic>).map(
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
    );
    final archives = (json['carModels'] as List).cast<Map<String, dynamic>>();
    _validate(components, materials, archives);
    return CarModel._(components, materials, archives);
  }

  static void _validate(
    List<CarComponent> components,
    Map<String, Map<String, Color>> materials,
    List<Map<String, dynamic>> archives,
  ) {
    final componentIds = components.map((part) => part.id).toSet();
    final archiveIds = archives.map((car) => car['car_model_id']).toSet();
    if (componentIds.length != components.length ||
        componentIds.length != carComponentIds.length ||
        !componentIds.containsAll(carComponentIds) ||
        archiveIds.length != archives.length ||
        archiveIds.any((id) => id is! String || id.isEmpty) ||
        !materials.containsKey('neutral') ||
        materials.values.any(
          (palette) => !palette.keys.toSet().containsAll(_paletteMaterialIds),
        ) ||
        components.any(
          (part) => part.faces.any(
            (face) => !_meshMaterialIds.contains(face.material),
          ),
        )) {
      throw const FormatException(
        'Invalid Evolution component, material, or car model ID.',
      );
    }
    for (final archive in archives) {
      final previous = archive['previous_car_model_id'];
      if (previous != null && !archiveIds.contains(previous)) {
        throw FormatException('Unknown previous car model: $previous');
      }
      for (final change in (archive['compare_changes'] as List? ?? const [])) {
        final component = (change as Map<String, dynamic>)['component_id'];
        if (component is! String || !componentIds.contains(component)) {
          throw FormatException('Unknown comparison component: $component');
        }
      }
    }
  }

  static Future<CarModel> load() async => CarModel(
    jsonDecode(await rootBundle.loadString('assets/evolution/car.json'))
        as Map<String, dynamic>,
  );
}
