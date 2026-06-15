import 'package:flutter/material.dart';

/// Paleta de marca eLashes (verde profundo + dorado).
/// Fuente única de color para toda la app.
class AppColors {
  AppColors._();

  static const Color brand = Color(0xFF0C4B36);
  static const Color brandDark = Color(0xFF144C38);
  static const Color gold = Color(0xFFBFA36F);
  static const Color background = Color(0xFFF6F8F7);
  static const Color surface = Colors.white;
  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF2E7D32);
}

/// Tema Material 3 de la app, derivado de [AppColors].
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
      secondary: AppColors.gold,
      surface: AppColors.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.brand,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.brand),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.brand),
      chipTheme: const ChipThemeData(
        selectedColor: AppColors.brand,
        showCheckmark: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.brandDark,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
