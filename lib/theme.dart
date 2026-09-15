import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final fg = isLight ? Colors.black : Colors.white;
  final bg = isLight ? Colors.white : Colors.black;
  final surface = isLight ? Colors.white : const Color(0xFF121212);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: Colors.black,
        brightness: brightness,
      ).copyWith(
        primary: fg,
        onPrimary: bg,
        secondary: fg,
        onSecondary: bg,
        surface: surface,
        onSurface: fg,
        primaryContainer: fg,
        onPrimaryContainer: bg,
        secondaryContainer: isLight ? Colors.black12 : Colors.white12,
        onSecondaryContainer: fg,
        outline: isLight ? Colors.black45 : Colors.white54,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: fg,
        foregroundColor: bg,
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? fg
            : (isLight ? Colors.white : Colors.black),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? fg.withValues(alpha: 0.5)
            : Colors.grey,
      ),
    ),
  );
}
