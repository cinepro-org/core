import 'package:flutter/material.dart';

/// defines the minimal cinepro manager theme inspired by the original cinepro design
class CineProTheme {
  static const accent = Color(0xfff30f17);
  static const ink = Color(0xff0a0a0a);
  static const paper = Color(0xffffffff);
  static const muted = Color(0xff666666);
  static const line = Color(0xffe8e8e8);
  static final actionCursor = WidgetStateProperty.resolveWith<MouseCursor>((
    states,
  ) {
    return states.contains(WidgetState.disabled)
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click;
  });

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      primary: accent,
      surface: paper,
      onSurface: ink,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      fontFamily: 'Segoe UI',
      useMaterial3: true,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: Color(0x22f30f17),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(accent),
          foregroundColor: WidgetStateProperty.all(paper),
          minimumSize: WidgetStateProperty.all(const Size(96, 42)),
          mouseCursor: actionCursor,
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(ink),
          minimumSize: WidgetStateProperty.all(const Size(96, 42)),
          mouseCursor: actionCursor,
          side: WidgetStateProperty.all(const BorderSide(color: line)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(mouseCursor: actionCursor),
      ),
      checkboxTheme: CheckboxThemeData(mouseCursor: actionCursor),
    );
  }
}
