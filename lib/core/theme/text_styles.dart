import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextTheme buildTextTheme(TextTheme base) =>
      GoogleFonts.interTextTheme(base).apply(
        bodyColor: base.bodyMedium?.color,
        displayColor: base.bodyMedium?.color,
      );
}
