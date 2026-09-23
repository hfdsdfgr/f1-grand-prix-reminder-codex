import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api_config.dart';

Future<void> main() async {
  ApiConfig.validate();
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(GrandPrixApp(preferences: preferences));
}
