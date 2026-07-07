import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/core/i18n/app_translations_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appTranslationsNotifier.value = AppTranslations.empty;
  });

  test('loadCachedThenRefresh loads cache immediately', () async {
    SharedPreferences.setMockInitialValues({
      'app_translations_v1': jsonEncode({
        'version': 4,
        'locales': {
          'uz': {'common.cancel': 'Bekor qilish'},
        },
      }),
    });

    final client = MockClient((_) async => http.Response('{"version":4}', 200));
    await AppTranslationsStore.instance.loadCachedThenRefresh(client: client);

    expect(appTranslationsNotifier.value.version, 4);
    expect(
      appTranslationsNotifier.value.byLang['uz']?['common.cancel'],
      'Bekor qilish',
    );
  });

  test('refresh skips bundle download when version is unchanged', () async {
    appTranslationsNotifier.value = const AppTranslations(
      version: 9,
      byLang: {
        'uz': {'common.cancel': 'Bekor qilish'},
      },
    );
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      if (request.url.toString().contains('/i18n/version')) {
        return http.Response('{"version":9}', 200);
      }
      fail('bundle should not be requested');
    });

    await AppTranslationsStore.instance.refresh(client: client);
    expect(calls, 1);
  });

  test('refresh replaces cache when backend version is newer', () async {
    final client = MockClient((request) async {
      if (request.url.toString().contains('/i18n/version')) {
        return http.Response('{"version":11}', 200);
      }
      return http.Response(
        jsonEncode({
          'version': 11,
          'locales': {
            'ru': {'common.cancel': 'Отменить'},
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await AppTranslationsStore.instance.refresh(client: client);

    expect(appTranslationsNotifier.value.version, 11);
    expect(
      appTranslationsNotifier.value.byLang['ru']?['common.cancel'],
      'Отменить',
    );
  });

  test('refresh ignores network or parse failures', () async {
    appTranslationsNotifier.value = const AppTranslations(
      version: 3,
      byLang: {
        'en': {'common.cancel': 'Cancel'},
      },
    );
    final client = MockClient((_) async => throw Exception('offline'));

    await AppTranslationsStore.instance.refresh(client: client);

    expect(appTranslationsNotifier.value.version, 3);
    expect(
      appTranslationsNotifier.value.byLang['en']?['common.cancel'],
      'Cancel',
    );
  });
}
