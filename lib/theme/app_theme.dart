import 'package:flutter/material.dart';

/// FLAME design language.
///
/// Warm fire palette — safe and welcoming for primary-school children.
/// Green is reserved for offline/ready status (never shown as a failure).
class FlameColors {
  FlameColors._();

  static const Color ember = Color(0xFFE4572E);
  static const Color flame = Color(0xFFF4783F);
  static const Color amber = Color(0xFFF5A524);
  static const Color glow = Color(0xFFFFD9A0);

  static const Color deepEmber = Color(0xFF2A1710);
  static const Color charcoal = Color(0xFF3E2A20);

  static const Color cream = Color(0xFFFFF8F0);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color ready = Color(0xFF1FA35C);
  static const Color readySoft = Color(0xFFE3F5EA);
  static const Color error = Color(0xFFC23B2E);
  static const Color errorSoft = Color(0xFFFBE9E7);
  static const Color ink = Color(0xFF2B1A12);
  static const Color inkSoft = Color(0xFF7A6A60);
  static const Color line = Color(0xFFF0E2D2);

  static const LinearGradient flameGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [flame, ember],
  );

  static const LinearGradient emberGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [deepEmber, charcoal],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: FlameColors.ember,
        primary: FlameColors.ember,
        secondary: FlameColors.amber,
        surface: FlameColors.surface,
        error: FlameColors.error,
      ),
      scaffoldBackgroundColor: FlameColors.cream,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      splashColor: FlameColors.glow.withValues(alpha: 0.35),
      highlightColor: FlameColors.glow.withValues(alpha: 0.18),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: FlameColors.ink,
        centerTitle: true,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: FlameColors.ink,
        displayColor: FlameColors.ink,
      ),
      cardTheme: CardThemeData(
        color: FlameColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: FlameColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FlameColors.ember,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FlameColors.ember,
          side: const BorderSide(color: FlameColors.flame),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: FlameColors.deepEmber,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: FlameColors.ember,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: FlameColors.inkSoft),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FlameColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FlameColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FlameColors.ember, width: 1.6),
        ),
      ),
    );
  }
}