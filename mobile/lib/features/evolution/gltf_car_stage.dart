import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'car_model.dart';

class GltfCarController {
  Scene? _scene;
  PerspectiveCamera? _camera;
  Set<String> _componentIds = const {};

  String? partAt(Offset point, Size size) {
    final scene = _scene, camera = _camera;
    if (scene == null || camera == null) return null;
    Node? node = scene.raycast(camera.screenPointToRay(point, size))?.node;
    while (node != null) {
      if (_componentIds.contains(node.name)) return node.name;
      node = node.parent;
    }
    return null;
  }

  void _attach(
    Scene scene,
    PerspectiveCamera camera,
    Iterable<String> componentIds,
  ) {
    _scene = scene;
    _camera = camera;
    _componentIds = componentIds.toSet();
  }

  void _updateCamera(PerspectiveCamera camera) => _camera = camera;

  void _detach(Scene scene) {
    if (identical(_scene, scene)) {
      _scene = null;
      _camera = null;
      _componentIds = const {};
    }
  }
}

class GltfCarStage extends StatefulWidget {
  const GltfCarStage({
    super.key,
    required this.model,
    required this.controller,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.selected,
    required this.team,
    required this.onReady,
    required this.onUnavailable,
  });

  final CarModel model;
  final GltfCarController controller;
  final double yaw, pitch, zoom;
  final String selected, team;
  final VoidCallback onReady, onUnavailable;

  @override
  State<GltfCarStage> createState() => _GltfCarStageState();
}

class _GltfCarStageState extends State<GltfCarStage> {
  static const _asset = 'assets/evolution/universal-car.glb';
  final _resources = ResourceGroup();
  final _parts = <String, Node>{};
  Scene? _scene;
  Node? _car;
  bool _ready = false, _failed = false;

  PerspectiveCamera get _camera {
    final horizontal = math.cos(widget.pitch), distance = 9 / widget.zoom;
    return PerspectiveCamera(
      fovRadiansY: 35 * math.pi / 180,
      position: vm.Vector3(
        -math.sin(widget.yaw) * horizontal * distance,
        .45 + math.sin(widget.pitch) * distance,
        math.cos(widget.yaw) * horizontal * distance,
      ),
      target: vm.Vector3(0, .45, 0),
      up: widget.pitch > 1.5 ? vm.Vector3(0, 0, -1) : vm.Vector3(0, 1, 0),
      fovNear: .1,
      fovFar: 40,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scene = Scene();
      _scene = scene;
      await Scene.initializeStaticResources();
      final car = await _resources.track(
        loadScene(_asset, applyStageTo: scene),
        release: () async {
          await releaseScene(_asset);
        },
      );
      if (!mounted) return;
      _car = car;
      scene.add(car);
      for (final node in car.meshNodes) {
        if (widget.model.components.any((part) => part.id == node.name)) {
          _parts[node.name] = node;
        }
      }
      if (_parts.length != widget.model.components.length) {
        throw StateError(
          '3D asset component mismatch: ${_parts.length}/'
          '${widget.model.components.length}',
        );
      }
      _applyAppearance();
      final camera = _camera;
      widget.controller._attach(scene, camera, _parts.keys);
      setState(() => _ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onReady();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onUnavailable();
      });
    }
  }

  @override
  void didUpdateWidget(covariant GltfCarStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready) return;
    widget.controller._updateCamera(_camera);
    if (oldWidget.selected != widget.selected ||
        oldWidget.team != widget.team) {
      _applyAppearance();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) _applyAppearance();
  }

  void _applyAppearance() {
    final selectedColor = Theme.of(context).colorScheme.primary;
    for (final entry in _parts.entries) {
      entry.value.highlightColor = entry.key == widget.selected
          ? vm.Vector4(selectedColor.r, selectedColor.g, selectedColor.b, 1)
          : null;
    }

    const materialOrder = [
      'body',
      'secondary',
      'carbon',
      'accent',
      'tyre',
      'hub',
    ];
    final palette = widget.model.materials[widget.team]!;
    for (final component in widget.model.components) {
      final node = _parts[component.id], mesh = _parts[component.id]?.mesh;
      if (node == null || mesh == null) continue;
      final used = materialOrder
          .where((name) => component.faces.any((face) => face.material == name))
          .toList();
      for (var i = 0; i < mesh.primitives.length && i < used.length; i++) {
        final key = used[i];
        final color = switch (key) {
          'tyre' => const Color(0xff303338),
          'hub' => const Color(0xff707980),
          _ => palette[key]!,
        };
        final material = mesh.primitives[i].material;
        if (material is PhysicallyBasedMaterial) {
          material
            ..baseColorFactor = vm.Vector4(color.r, color.g, color.b, 1)
            ..metallicFactor = 0
            ..roughnessFactor = .8;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _failed) return const SizedBox.expand();
    final camera = _camera;
    widget.controller._updateCamera(camera);
    return SceneView(_scene!, camera: camera);
  }

  @override
  void dispose() {
    final scene = _scene;
    if (scene != null) {
      widget.controller._detach(scene);
      final car = _car;
      if (car != null) scene.remove(car);
    }
    _resources.dispose();
    super.dispose();
  }
}
