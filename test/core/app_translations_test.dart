import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';

void main() {
  tearDown(() {
    appTranslationsNotifier.value = AppTranslations.empty;
  });

  test('tr falls back to inline defaults when there is no bundle', () {
    expect(
      tr(
        const Locale('ru'),
        'common.cancel',
        uz: 'Bekor qilish',
        ru: 'Отмена',
        en: 'Cancel',
      ),
      'Отмена',
    );
  });

  test('tr prefers backend override for the active language', () {
    appTranslationsNotifier.value = const AppTranslations(
      version: 7,
      byLang: {
        'uz': {'common.cancel': 'Bekor qiling'},
        'ru': {'common.cancel': 'Отменить'},
      },
    );

    expect(
      tr(
        const Locale('ru'),
        'common.cancel',
        uz: 'Bekor qilish',
        ru: 'Отмена',
        en: 'Cancel',
      ),
      'Отменить',
    );
  });

  test('tr keeps inline default when backend bundle misses the key', () {
    appTranslationsNotifier.value = const AppTranslations(
      version: 7,
      byLang: {
        'ru': {'other.key': 'Что-то другое'},
      },
    );

    expect(
      tr(
        const Locale('en'),
        'common.cancel',
        uz: 'Bekor qilish',
        ru: 'Отмена',
        en: 'Cancel',
      ),
      'Cancel',
    );
  });
}
