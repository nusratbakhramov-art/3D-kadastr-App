import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const Color brandGreenDark = Color(0xFF034112);
  static const Color brandGreenDeep = Color(0xFF011606);
  static const Color brandGreen = Color(0xFF0A6B23);
  static const Color splashGreen = Color(0xFF00E135);
  static const Color greenBlack = Color(0xFF000702);

  static const Color textBlack = Color(0xFF18181B);
  static const Color buttonTextBlack = Color(0xFF151515);

  static const Color surface = Color(0xFFF5F7F4);
  static const Color onSurface = Color(0xFF0E1A12);
  static const Color outline = Color(0xFFCBD5CE);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandGreenDark, brandGreenDeep],
  );
}
