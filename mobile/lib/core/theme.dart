import 'package:flutter/material.dart';

ThemeData raceTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFFB42318),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xFF161719) : Colors.white,
        onSurface: dark ? const Color(0xFFF3F4F5) : const Color(0xFF202124),
        onSurfaceVariant: dark
            ? const Color(0xFFB6BBC2)
            : const Color(0xFF5F6368),
        primary: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB42318),
        outlineVariant: dark
            ? const Color(0xFF44484D)
            : const Color(0xFFDADCE0),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 44,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
      ),
      headlineMedium: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5),
      bodySmall: TextStyle(fontSize: 14, height: 1.5),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
    ),
  );
}
