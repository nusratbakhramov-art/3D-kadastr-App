import 'package:flutter/material.dart';

enum ServiceId { kadastr3d, aiValuation, calculator }

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.accent,
    required this.layout,
  });

  final ServiceId id;
  final String title;
  final String subtitle;
  final String asset;
  final Color accent;
  final ServiceLayout layout;
}

enum ServiceLayout { square, wide }

class ServiceStrings {
  const ServiceStrings._();

  static String pageTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Услуги',
    'en' => 'Services',
    _ => 'Xizmatlar',
  };

  static String kadastrTitle(Locale l) => switch (l.languageCode) {
    'ru' => '3D кадастр',
    'en' => '3D cadastre',
    _ => '3D kadastr',
  };

  static String kadastrSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Профессиональный LiDAR скан + QR отчёт. Только жильё.',
    'en' => 'Professional LiDAR scan + QR report. Residential only.',
    _ => 'Professional LiDAR skan + QR hisobot. Faqat turar-joy.',
  };

  static String aiTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'AI Оценка',
    'en' => 'AI Valuation',
    _ => 'AI Baholash',
  };

  static String aiSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Оценка стоимости недвижимости с помощью ИИ.',
    'en' => 'Real estate valuation powered by AI.',
    _ => 'Sun\'iy intellekt yordamida ko\'chmas mulk qiymatini aniqlash.',
  };

  static String calculatorTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Онлайн калькулятор',
    'en' => 'Online calculator',
    _ => 'Onlayn Kalkulyator',
  };

  static String calculatorSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Расчёт стоимости архитектуры, дизайна и строительства.',
    'en' => 'Calculate architecture, design and construction costs.',
    _ => 'Arxitektura, dizayn, qurilish narxlarini hisoblash.',
  };
}
