import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';

void main() {
  tearDown(() {
    appTranslationsNotifier.value = AppTranslations.empty;
  });

  test('tr returns the key itself when there is no bundle', () {
    // No inline fallback: an absent key surfaces raw so gaps are visible.
    expect(tr(const Locale('ru'), 'common.cancel'), 'common.cancel');
  });

  test('tr prefers backend override for the active language', () {
    appTranslationsNotifier.value = const AppTranslations(
      version: 7,
      byLang: {
        'uz': {'common.cancel': 'Bekor qiling'},
        'ru': {'common.cancel': 'Отменить'},
      },
    );

    expect(tr(const Locale('ru'), 'common.cancel'), 'Отменить');
  });

  test('tr returns the key when the bundle misses it', () {
    appTranslationsNotifier.value = const AppTranslations(
      version: 7,
      byLang: {
        'ru': {'other.key': 'Что-то другое'},
      },
    );

    expect(tr(const Locale('en'), 'common.cancel'), 'common.cancel');
  });

  test('uz is the default language for non-ru/en locales', () {
    appTranslationsNotifier.value = const AppTranslations(
      version: 1,
      byLang: {
        'uz': {'common.cancel': 'Bekor qilish'},
      },
    );

    expect(tr(const Locale('uz'), 'common.cancel'), 'Bekor qilish');
    // Unknown language code falls through to uz.
    expect(tr(const Locale('kk'), 'common.cancel'), 'Bekor qilish');
  });
}
