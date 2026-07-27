import 'dart:ui';

import '../../core/i18n/app_translations.dart';

class OnboardingPageData {
  const OnboardingPageData({
    required this.titleKey,
    required this.descriptionKey,
    required this.mockupAsset,
  });

  final String titleKey;
  final String descriptionKey;
  final String mockupAsset;

  String title(Locale locale) => tr(locale, titleKey);

  String description(Locale locale) => tr(locale, descriptionKey);
}

const String _mockup = 'assets/images/mockup-onboarding.png';

const List<OnboardingPageData> onboardingPages = [
  OnboardingPageData(
    mockupAsset: _mockup,
    titleKey: 'onboarding.page1.title',
    descriptionKey: 'onboarding.page1.desc',
  ),
  OnboardingPageData(
    mockupAsset: _mockup,
    titleKey: 'onboarding.page2.title',
    descriptionKey: 'onboarding.page2.desc',
  ),
  OnboardingPageData(
    mockupAsset: _mockup,
    titleKey: 'onboarding.page3.title',
    descriptionKey: 'onboarding.page3.desc',
  ),
];

class AppLocale {
  const AppLocale._();

  static const Locale uz = Locale('uz');
  static const Locale ru = Locale('ru');
  static const Locale en = Locale('en');

  static const List<Locale> all = [uz, ru, en];

  static String displayName(Locale locale) => switch (locale.languageCode) {
    'ru' => tr(locale, 'onboarding.lang.ru'),
    'en' => tr(locale, 'onboarding.lang.en'),
    _ => tr(locale, 'onboarding.lang.uz'),
  };

  static String flagAsset(Locale locale) => switch (locale.languageCode) {
    'uz' => 'assets/images/flags/uz.svg',
    'ru' => 'assets/images/flags/ru.svg',
    'en' => 'assets/images/flags/en.svg',
    _ => 'assets/images/flags/uz.svg',
  };

  static String skipLabel(Locale locale) => tr(locale, 'onboarding.skip');

  static String continueLabel(Locale locale) =>
      tr(locale, 'onboarding.continue');

  static String backLabel(Locale locale) => tr(locale, 'onboarding.back');

  static String chooseLanguageTitle(Locale locale) =>
      tr(locale, 'onboarding.choose_language');
}
