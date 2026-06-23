import 'package:flutter/material.dart';

enum ServiceId { kadastr3d, aiValuation, calculator, smetaPro }

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
    'ru' => 'Кадастр',
    'en' => 'Cadastre',
    _ => 'Kadastr',
  };

  static String kadastrSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Рассчитайте стоимость услуг и оставьте заявку.',
    'en' => 'Calculate service prices and submit an application.',
    _ => 'Xizmatlar narxini hisoblang va ariza qoldiring.',
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

  static String smetaProTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'ABC смета (для смет)',
    'en' => 'ABC smeta (for estimators)',
    _ => 'ABC smeta (smetachilar uchun)',
  };

  static String smetaProSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Профессиональная смета по СНиР через ABC-UZ. Форма N5/N6.',
    'en' => 'Professional СНиР smeta priced by ABC-UZ. Form N5/N6 output.',
    _ => "SNiR bo'yicha professional smeta — ABC-UZ asosida. Forma N5/N6 vedomosti.",
  };
}
