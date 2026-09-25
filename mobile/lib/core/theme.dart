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
        seedColor: const Color(0xFFFF4055),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xFF090B0C) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xFF111416)
            : const Color(0xFFF5F5F6),
        surfaceContainerHigh: dark
            ? const Color(0xFF111416)
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
        onSurface: dark ? const Color(0xFFF2F0EB) : const Color(0xFF202124),
        onSurfaceVariant: dark
            ? const Color(0xFFA6ABB4)
            : const Color(0xFF5F6368),
        primary: dark ? const Color(0xFFFF4055) : const Color(0xFFB52B43),
        onPrimary: dark ? const Color(0xFF18080C) : Colors.white,
        outlineVariant: dark
            ? const Color(0xFF3B4143)
            : const Color(0xFFDADCE0),
      );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Barlow',
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
      labelMedium: const TextStyle(
        fontFamily: 'BarlowCondensed',
        fontSize: 12,
        height: 1.25,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'BarlowCondensed',
        fontSize: 14,
        height: 1.3,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Newsreader',
        fontSize: 44,
        height: 1.02,
        fontWeight: FontWeight.w500,
        letterSpacing: -.5,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'Newsreader',
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      headlineSmall: const TextStyle(
        fontFamily: 'Newsreader',
        fontSize: 24,
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
      bodyMedium: TextStyle(fontSize: 16, height: 1.4),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.4,
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
      height: 64,
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
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
