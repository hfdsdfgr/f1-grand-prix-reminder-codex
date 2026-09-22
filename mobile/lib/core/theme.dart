import 'package:flutter/material.dart';

abstract final class RaceSpace {
  static const small = 8.0, medium = 16.0, large = 24.0, section = 32.0;
  static const radius = 6.0, contentWidth = 760.0;
  static const page = EdgeInsets.fromLTRB(24, 24, 24, 40);
}

ThemeData raceTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF6578),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xFF0C0D0F) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xFF17191D)
            : const Color(0xFFF5F5F6),
        surfaceContainerHigh: dark
            ? const Color(0xFF17191D)
            : const Color(0xFFF5F5F6),
        surfaceContainerHighest: dark
            ? const Color(0xFF202328)
            : const Color(0xFFEEEEEF),
        secondaryContainer: dark
            ? const Color(0xFF282126)
            : const Color(0xFFF6E3E8),
        onSecondaryContainer: dark
            ? const Color(0xFFF5F5F6)
            : const Color(0xFF202124),
        surfaceTint: Colors.transparent,
        onSurface: dark ? const Color(0xFFF3F4F5) : const Color(0xFF202124),
        onSurfaceVariant: dark
            ? const Color(0xFFA6ABB4)
            : const Color(0xFF5F6368),
        primary: dark ? const Color(0xFFFF6578) : const Color(0xFFB52B43),
        onPrimary: dark ? const Color(0xFF18080C) : Colors.white,
        outlineVariant: dark
            ? const Color(0xFF30343B)
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
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: TextTheme(
      displaySmall: TextStyle(
        fontSize: 38,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
      ),
      headlineMedium: const TextStyle(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      headlineSmall: const TextStyle(
        fontSize: 23,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: .5,
    ),
    iconTheme: IconThemeData(size: 20, color: scheme.onSurfaceVariant),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RaceSpace.radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RaceSpace.radius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RaceSpace.radius),
      ),
      side: BorderSide.none,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: RaceSpace.medium),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RaceSpace.radius),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(strokeWidth: 2),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
