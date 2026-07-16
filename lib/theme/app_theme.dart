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
        surface: AppColors.lightBackground,
        onSurface: AppColors.onSurface,
      ),
      scaffoldBackgroundColor: AppColors.lightBackground,
      fontFamily: textFont,
    );

    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme, AppColors.onSurface),
      // titleTextStyle is deliberately NOT set here. AppBar resolves the title
      // as `widget.titleTextStyle ?? appBarTheme.titleTextStyle ??
      // defaults.titleTextStyle?.copyWith(color: foregroundColor)` — so naming
      // one here permanently blocks foregroundColor from reaching the title,
      // and every screen that overrides the bar's background kept getting a
      // hardcoded white title (invisible on a light bar). Leaving it null lets
      // the M3 default (textTheme.titleLarge) take foregroundColor. The font
      // and size live in titleLarge, so the bars look identical.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.brandGreenDark,
        foregroundColor: Colors.white,
        centerTitle: false,
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
        surface: AppColors.darkSurface,
        onSurface: Colors.white,
        outline: AppColors.darkOutline,
        outlineVariant: AppColors.darkDivider,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      fontFamily: textFont,
    );

    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme, Colors.white),
      cardTheme: const CardThemeData(
        color: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkDivider,
        thickness: 1,
      ),
      // titleTextStyle omitted deliberately — see the light theme's note.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandGreen,
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
      // 20, not 18: this is what an AppBar title resolves to in M3
      // (defaults.titleTextStyle => textTheme.titleLarge), and the bars used to
      // get 20 from AppBarTheme.titleTextStyle before that was removed. Nothing
      // else reads titleLarge, so this only governs app bars.
      titleLarge: display(20, FontWeight.w700),
      titleMedium: text(16, FontWeight.w500),
      titleSmall: text(14, FontWeight.w500),
      bodyLarge: text(16, FontWeight.w400),
      bodyMedium: text(14, FontWeight.w400),
      bodySmall: text(12, FontWeight.w400),
      labelLarge: text(14, FontWeight.w500),
    );
  }
}
