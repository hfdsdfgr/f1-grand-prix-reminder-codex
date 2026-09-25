import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api_config.dart';

Future<void> main() async {
  ApiConfig.validate();
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Newsreader', 'Barlow', 'BarlowCondensed']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/$font-OFL.txt'));
    }
  });
  final preferences = await SharedPreferences.getInstance();
  runApp(GrandPrixApp(preferences: preferences));
}
