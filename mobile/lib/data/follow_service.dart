import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FollowEntry {
  final String id, name;
  const FollowEntry({required this.id, required this.name});

  Map<String, String> toJson() => {'id': id, 'name': name};
  factory FollowEntry.fromJson(Map<String, dynamic> json) =>
      FollowEntry(id: json['id'] as String, name: json['name'] as String);
}

class FollowService extends ChangeNotifier {
  static const _driversKey = 'followedDriverIds';
  static const _teamsKey = 'followedTeamIds';
  final SharedPreferences _preferences;
  late List<FollowEntry> _drivers = _read(_driversKey);
  late List<FollowEntry> _teams = _read(_teamsKey);

  FollowService(this._preferences);

  List<FollowEntry> get drivers => List.unmodifiable(_drivers);
  List<FollowEntry> get teams => List.unmodifiable(_teams);
  bool followsDriver(String id) => _drivers.any((entry) => entry.id == id);
  bool followsTeam(String id) => _teams.any((entry) => entry.id == id);

  List<FollowEntry> _read(String key) {
    final raw = _preferences.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => FollowEntry.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> toggleDriver(String id, String name) => _toggle(
    key: _driversKey,
    entries: _drivers,
    id: id,
    name: name,
    update: (entries) => _drivers = entries,
  );

  Future<void> toggleTeam(String id, String name) => _toggle(
    key: _teamsKey,
    entries: _teams,
    id: id,
    name: name,
    update: (entries) => _teams = entries,
  );

  Future<void> _toggle({
    required String key,
    required List<FollowEntry> entries,
    required String id,
    required String name,
    required ValueChanged<List<FollowEntry>> update,
  }) async {
    final index = entries.indexWhere((entry) => entry.id == id);
    final next = [...entries];
    if (index < 0) {
      next.add(FollowEntry(id: id, name: name));
    } else {
      next.removeAt(index);
    }
    await _preferences.setString(
      key,
      jsonEncode(next.map((entry) => entry.toJson()).toList()),
    );
    update(next);
    notifyListeners();
  }
}
