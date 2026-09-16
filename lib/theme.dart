import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        // Zonder deze override kiest ColorScheme.fromSeed (seed = zwart, dus
        // zonder hue) een willekeurig getinte grijstint voor onSurfaceVariant
        // — ListTile-subtitels en leading-icons werden daardoor nauwelijks
        // leesbaar in lichte modus.
        onSurfaceVariant: isLight ? Colors.black87 : Colors.white70,
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
      // Android-statusbalk moet exact de achtergrondkleur volgen (geen
      // afwijkende systeemkleur boven de app-inhoud).
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: bg,
        statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
        statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
      ),
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
    // Alle segmenten (niet alleen de geselecteerde) krijgen dezelfde
    // volle achtergrond — selectie wordt getoond via het vinkje, niet via
    // een afwijkende kleur of scheidingslijntjes tussen segmenten.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(fg),
        foregroundColor: WidgetStateProperty.all(bg),
        iconColor: WidgetStateProperty.all(bg),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? fg
            // Wit bolletje op lichte achtergrond (of zwart op donkere) was
            // vrijwel onzichtbaar — de uit-stand moet juist contrasteren.
            : (isLight ? Colors.grey[700] : Colors.grey[300]),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? fg.withValues(alpha: 0.5)
            : Colors.grey,
      ),
    ),
    // ColorScheme.fromSeed(seedColor: Colors.black) geeft onSurfaceVariant
    // een willekeurig getinte, lichte grijstint (zwart heeft geen hue) —
    // zonder deze expliciete override zijn ListTile-subtitels en
    // leading-icons nauwelijks leesbaar in lichte modus.
    listTileTheme: ListTileThemeData(
      iconColor: isLight ? Colors.black87 : Colors.white70,
      textColor: fg,
      subtitleTextStyle: TextStyle(
        color: isLight ? Colors.black54 : Colors.white60,
        fontSize: 12,
      ),
    ),
    // Zelfde reden als onSurfaceVariant hierboven: de auto-gegenereerde
    // outlineVariant (gebruikt door Divider) is met een zwarte seed
    // nauwelijks te onderscheiden van de achtergrond.
    dividerTheme: DividerThemeData(
      color: isLight ? Colors.black26 : Colors.white38,
    ),
  );
}
