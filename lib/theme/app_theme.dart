import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF23272E);
  static const secondary = Color(0xFF8C929B);
  static const accent = Color(0xFF458CF4);
  static const canvas = Color(0xFFF8F9FB);
  static const line = Color(0xFFEDF0F4);
  static const darkSurface = Color(0xFF0F1115);
  static const darkInk = Color(0xFFE8EAED);
  static const darkSecondary = Color(0xFF9AA0A6);
  static const darkCanvas = Color(0xFF1A1D22);
  static const darkLine = Color(0xFF2A2D33);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 30,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: AppColors.ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink),
      ),
      dividerColor: AppColors.line,
      iconTheme: const IconThemeData(color: AppColors.ink),
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkSurface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 30,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: AppColors.darkInk,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: AppColors.darkInk,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.6,
          color: AppColors.darkInk,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: AppColors.darkInk,
        ),
      ),
      dividerColor: AppColors.darkLine,
      iconTheme: const IconThemeData(color: AppColors.darkInk),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.darkInk,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkCanvas,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.darkCanvas),
    );
  }
}
