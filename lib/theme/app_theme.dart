import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  const AppTheme._();

  static const String displayFont = 'MTSCompact';
  static const String textFont = 'MTSText';

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brandGreenDark,
        primary: AppColors.brandGreenDark,
        onPrimary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: textFont,
    );

    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme, AppColors.onSurface),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.brandGreenDark,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandGreenDark,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontFamily: displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brandGreenDark,
        brightness: Brightness.dark,
        primary: AppColors.brandGreen,
        onPrimary: Colors.white,
        surface: AppColors.brandGreenDeep,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.brandGreenDeep,
      fontFamily: textFont,
    );

    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme, Colors.white),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, Color color) {
    TextStyle display(double size, FontWeight w) => TextStyle(
      fontFamily: displayFont,
      fontWeight: w,
      fontSize: size,
      color: color,
    );
    TextStyle text(double size, FontWeight w) => TextStyle(
      fontFamily: textFont,
      fontWeight: w,
      fontSize: size,
      color: color,
    );

    return base.copyWith(
      displayLarge: display(48, FontWeight.w900),
      displayMedium: display(36, FontWeight.w700),
      displaySmall: display(28, FontWeight.w700),
      headlineLarge: display(24, FontWeight.w700),
      headlineMedium: display(20, FontWeight.w700),
      headlineSmall: display(18, FontWeight.w500),
      titleLarge: display(18, FontWeight.w700),
      titleMedium: text(16, FontWeight.w500),
      titleSmall: text(14, FontWeight.w500),
      bodyLarge: text(16, FontWeight.w400),
      bodyMedium: text(14, FontWeight.w400),
      bodySmall: text(12, FontWeight.w400),
      labelLarge: text(14, FontWeight.w500),
    );
  }
}
