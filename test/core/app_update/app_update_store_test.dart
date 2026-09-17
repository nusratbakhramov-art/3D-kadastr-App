/// Yangilanish tekshiruvi — kesh, throttle va XATOGA CHIDAMLILIK.
///
/// Eng muhim tasdiq: tarmoq/server nima qilishidan qat'i nazar ilova
/// bloklanmaydi. Bloklovchi holat FAQAT backend `required=true` qaytarganда.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/core/app_update/app_release.dart';
import 'package:kadastr/core/app_update/app_update_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _payload({
  bool hasUpdate = true,
  bool required = false,
  String version = '1.0.6',
  int? build = 55,
  String lang = 'uz',
  String? storeUrl = 'https://apps.apple.com/app/id6744487945',
  String? imageUrl,
}) => {
  'has_update': hasUpdate,
  'required': required,
  'platform': 'ios',
  'version': version,
  'build_number': build,
  'min_supported_version': '1.0.5',
  'title': 'Yangi versiya',
  'subtitle': 'Tezroq',
  'description': 'Xatolar tuzatildi',
  'image_url': imageUrl,
  'store_url': storeUrl,
  'lang': lang,
};

MockClient _json(Map<String, dynamic> body, {int status = 200}) => MockClient(
  (_) async => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppUpdateStore.instance.resetForTest();
  });

  test('no update available leaves the app untouched', () async {
    await AppUpdateStore.instance.refresh(
      client: _json(_payload(hasUpdate: false, required: false)),
    );
    final r = appReleaseNotifier.value;
    expect(r.hasUpdate, isFalse);
    expect(r.isBlocking, isFalse);
    expect(r.isOptional, isFalse);
  });

  test('optional update is offered but never blocking', () async {
    await AppUpdateStore.instance.refresh(client: _json(_payload()));
    final r = appReleaseNotifier.value;
    expect(r.isOptional, isTrue);
    expect(r.isBlocking, isFalse);
    expect(r.title, 'Yangi versiya');
    expect(r.storeUrl, startsWith('https://apps.apple.com'));
  });

  test('required update blocks', () async {
    await AppUpdateStore.instance.refresh(
      client: _json(_payload(required: true)),
    );
    expect(appReleaseNotifier.value.isBlocking, isTrue);
  });

  test('required without has_update never blocks', () async {
    // Backend buni qaytarmasligi kerak, lekin mijoz ham himoyalangan bo'lsin.
    await AppUpdateStore.instance.refresh(
      client: _json(_payload(hasUpdate: false, required: true)),
    );
    expect(appReleaseNotifier.value.isBlocking, isFalse);
  });

  // ── Xatolar: ilova HECH QACHON bloklanmaydi ────────────────────────────
  test('network failure keeps the app usable', () async {
    final client = MockClient((_) async => throw const SocketExceptionStub());
    await AppUpdateStore.instance.refresh(client: client);
    expect(appReleaseNotifier.value.hasUpdate, isFalse);
    expect(appReleaseNotifier.value.isBlocking, isFalse);
  });

  test('server 500 keeps the app usable', () async {
    await AppUpdateStore.instance.refresh(
      client: MockClient((_) async => http.Response('boom', 500)),
    );
    expect(appReleaseNotifier.value.isBlocking, isFalse);
  });

  test('malformed json keeps the app usable', () async {
    await AppUpdateStore.instance.refresh(
      client: MockClient((_) async => http.Response('not json at all', 200)),
    );
    expect(appReleaseNotifier.value.isBlocking, isFalse);
  });

  test('a non-object json body keeps the app usable', () async {
    await AppUpdateStore.instance.refresh(
      client: MockClient((_) async => http.Response('[1,2,3]', 200)),
    );
    expect(appReleaseNotifier.value.isBlocking, isFalse);
  });

  test('a later failure does not erase an earlier required verdict', () async {
    await AppUpdateStore.instance.refresh(
      client: _json(_payload(required: true)),
    );
    expect(appReleaseNotifier.value.isBlocking, isTrue);
    // Offline bo'lib qoldi — bloklash saqlanadi (aks holda majburiy
    // yangilanishni internetni o'chirib chetlab o'tish mumkin bo'lardi).
    await AppUpdateStore.instance.refresh(
      force: true,
      client: MockClient((_) async => throw const SocketExceptionStub()),
    );
    expect(appReleaseNotifier.value.isBlocking, isTrue);
  });

  // ── Kesh va throttle ──────────────────────────────────────────────────
  test('response is cached and read back on the next cold start', () async {
    await AppUpdateStore.instance.refresh(client: _json(_payload()));
    AppUpdateStore.instance.resetForTest();
    expect(appReleaseNotifier.value.hasUpdate, isFalse); // tozalandi

    // Sovuq start: keshdan o'qiydi, so'ng tarmoq yiqilsa ham kesh qoladi.
    await AppUpdateStore.instance.loadCachedThenRefresh(
      client: MockClient((_) async => throw const SocketExceptionStub()),
    );
    expect(appReleaseNotifier.value.hasUpdate, isTrue);
    expect(appReleaseNotifier.value.version, '1.0.6');
  });

  test('cold start always checks, even inside the throttle window', () async {
    var calls = 0;
    MockClient counting() => MockClient((_) async {
      calls += 1;
      return http.Response(jsonEncode(_payload()), 200);
    });

    await AppUpdateStore.instance.refresh(client: counting());
    expect(calls, 1);
    // Ilovani qayta ochish: throttle prefs'da saqlanadi, lekin sovuq start
    // baribir so'raydi — aks holda admin relizni MAJBURIY qilganда
    // foydalanuvchi buni 6 soatgacha ko'rmasdi.
    await AppUpdateStore.instance.loadCachedThenRefresh(client: counting());
    expect(calls, 2);
  });

  test('resume within the throttle window does not hit the network', () async {
    var calls = 0;
    MockClient counting() => MockClient((_) async {
      calls += 1;
      return http.Response(jsonEncode(_payload()), 200);
    });

    await AppUpdateStore.instance.refresh(client: counting());
    expect(calls, 1);
    // Fondan qaytish — 6 soat o'tmagan, so'rov YUBORILMAYDI.
    await AppUpdateStore.instance.refresh(client: counting());
    expect(calls, 1);
    // force: qo'lda qayta urinish throttle'ni chetlab o'tadi.
    await AppUpdateStore.instance.refresh(force: true, client: counting());
    expect(calls, 2);
  });

  test('switching locale invalidates the cached texts', () async {
    await AppUpdateStore.instance.refresh(client: _json(_payload(lang: 'uz')));
    AppUpdateStore.instance.resetForTest();

    // Endi ilova ruscha — keshdagi o'zbekcha matn KO'RSATILMAYDI, so'rov
    // ketadi va ruscha javob keladi.
    var asked = 0;
    final client = MockClient((request) async {
      asked += 1;
      expect(request.url.queryParameters['lang'], 'ru');
      return http.Response(jsonEncode(_payload(lang: 'ru')), 200);
    });
    await AppUpdateStore.instance.loadCachedThenRefresh(
      client: client,
      lang: 'ru',
    );
    expect(asked, 1);
    expect(appReleaseNotifier.value.lang, 'ru');
  });

  test('the request carries platform, version and build', () async {
    late Uri seen;
    await AppUpdateStore.instance.refresh(
      client: MockClient((request) async {
        seen = request.url;
        return http.Response(jsonEncode(_payload()), 200);
      }),
    );
    expect(seen.path, endsWith('/releases/latest'));
    expect(seen.queryParameters['platform'], anyOf('ios', 'android'));
    expect(seen.queryParameters['current_version'], isNotEmpty);
    expect(seen.queryParameters['build_number'], isNotEmpty);
  });

  // ── Model ─────────────────────────────────────────────────────────────
  test('missing optional image and store url decode to null', () async {
    await AppUpdateStore.instance.refresh(
      client: _json(_payload(storeUrl: null, imageUrl: null)),
    );
    expect(appReleaseNotifier.value.imageUrl, isNull);
    expect(appReleaseNotifier.value.storeUrl, isNull);
    // Havola yo'qligi taklifni bekor qilmaydi — tugma zaxira havolani ochadi.
    expect(appReleaseNotifier.value.isOptional, isTrue);
  });

  test('blank strings are treated as absent', () {
    final r = AppRelease.fromJson({
      'has_update': true,
      'image_url': '   ',
      'store_url': '',
    });
    expect(r.imageUrl, isNull);
    expect(r.storeUrl, isNull);
  });

  test('release key distinguishes builds of the same version', () {
    final a = AppRelease.fromJson(_payload(version: '1.0.6', build: 55));
    final b = AppRelease.fromJson(_payload(version: '1.0.6', build: 56));
    expect(a.key, isNot(b.key));
  });
}

/// `MockClient` ichidan otiladigan tarmoq xatosi (dart:io'ga bog'lanmaslik
/// uchun o'z turi).
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub: tarmoq yo\'q';
}
