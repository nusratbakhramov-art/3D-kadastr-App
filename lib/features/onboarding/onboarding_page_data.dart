import 'dart:ui';

class OnboardingPageData {
  const OnboardingPageData({
    required this.titles,
    required this.descriptions,
    required this.mockupAsset,
  });

  final Map<String, String> titles;
  final Map<String, String> descriptions;
  final String mockupAsset;

  String title(Locale locale) =>
      titles[locale.languageCode] ?? titles['uz'] ?? titles.values.first;

  String description(Locale locale) =>
      descriptions[locale.languageCode] ??
      descriptions['uz'] ??
      descriptions.values.first;
}

const String _mockup = 'assets/images/mockup-onboarding.png';

const List<OnboardingPageData> onboardingPages = [
  OnboardingPageData(
    mockupAsset: _mockup,
    titles: {
      'uz': '3D KADASTR XIZMATI',
      'ru': '3D КАДАСТР',
      'en': '3D CADASTRE',
    },
    descriptions: {
      'uz':
          "Professional LiDAR skanerlash texnologiyasi yordamida ko'chmas mulkingizni yuqori aniqlikda 3D formatda xaritaga tushiring.",
      'ru':
          'Профессиональная технология LiDAR-сканирования позволяет отображать недвижимость в 3D-формате с высокой точностью.',
      'en':
          'Professional LiDAR scanning technology lets you map real estate in 3D with maximum precision.',
    },
  ),
  OnboardingPageData(
    mockupAsset: _mockup,
    titles: {'uz': 'AI BAHOLASH', 'ru': 'AI ОЦЕНКА', 'en': 'AI VALUATION'},
    descriptions: {
      'uz':
          "Sun'iy intellekt obyekt qiymatini bir nechta manba asosida avtomatik hisoblaydi.",
      'ru':
          'Искусственный интеллект автоматически рассчитывает стоимость объекта по нескольким источникам.',
      'en':
          'Artificial intelligence automatically calculates object value using multiple data sources.',
    },
  ),
  OnboardingPageData(
    mockupAsset: _mockup,
    titles: {
      'uz': 'MARKET VA KALKULYATOR',
      'ru': 'МАРКЕТ И КАЛЬКУЛЯТОР',
      'en': 'MARKET & CALCULATOR',
    },
    descriptions: {
      'uz':
          '3D modellar katalogi va arxitektura/dizayn/qurilish narxlarini hisoblash.',
      'ru':
          'Каталог 3D-моделей и расчёт стоимости архитектуры, дизайна и строительства.',
      'en':
          '3D model catalog and pricing calculator for architecture, design and construction.',
    },
  ),
];

class AppLocale {
  const AppLocale._();

  static const Locale uz = Locale('uz');
  static const Locale ru = Locale('ru');
  static const Locale en = Locale('en');

  static const List<Locale> all = [uz, ru, en];

  static String displayName(Locale locale) => switch (locale.languageCode) {
    'uz' => "O'zbekcha",
    'ru' => 'Русский',
    'en' => 'English',
    _ => locale.languageCode,
  };

  static String flagAsset(Locale locale) => switch (locale.languageCode) {
    'uz' => 'assets/images/flags/uz.svg',
    'ru' => 'assets/images/flags/ru.svg',
    'en' => 'assets/images/flags/en.svg',
    _ => 'assets/images/flags/uz.svg',
  };

  static String skipLabel(Locale locale) => switch (locale.languageCode) {
    'uz' => "O'tkazib yuborish",
    'ru' => 'Пропустить',
    'en' => 'Skip',
    _ => "O'tkazib yuborish",
  };

  static String continueLabel(Locale locale) => switch (locale.languageCode) {
    'uz' => 'Davom etish',
    'ru' => 'Продолжить',
    'en' => 'Continue',
    _ => 'Davom etish',
  };

  static String backLabel(Locale locale) => switch (locale.languageCode) {
    'uz' => 'Ortga',
    'ru' => 'Назад',
    'en' => 'Back',
    _ => 'Ortga',
  };

  static String chooseLanguageTitle(Locale locale) =>
      switch (locale.languageCode) {
        'uz' => 'Tilni tanlang',
        'ru' => 'Выберите язык',
        'en' => 'Choose language',
        _ => 'Tilni tanlang',
      };
}
