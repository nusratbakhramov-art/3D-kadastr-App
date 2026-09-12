import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/panorama/data/pano_api.dart';
import 'package:kadastr/features/panorama/screens/pano_capture_flow.dart';

/// Tikish CHEKSIZ kutilmasin.
///
/// ⚠️ NEGA BU TEST BOR. Kutish ekranida orqaga qaytish ATAYLAB yopiq
/// (`canPop: false`) va polling o'zi hech qachon tugamaydi. Server ishni
/// `queued` da qoldirsa — masalan `celery-panorama` worker'i ko'tarilmagan
/// bo'lsa — foydalanuvchi aylanayotgan doirani CHEKSIZ kuzatardi va
/// ilovani majburan yopishdan boshqa chorasi qolmasdi. 2026-09-12 da
/// prodda aynan shunday holat yuzaga keldi.
void main() {
  setUp(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  tearDown(() => appTranslationsNotifier.value = AppTranslations.empty);

  test('kStitchTimeout o\'lchangan vaqtdan ANCHA katta', () {
    // Tikish ~32 s (4096×2048, 28 kadr). Chegara undan kamida 5 barobar
    // katta bo'lsin — navbatda kutish ham qo'shiladi (concurrency 1).
    expect(
      PanoCaptureFlowState.kStitchTimeout.inSeconds,
      greaterThanOrEqualTo(32 * 5),
      reason: 'juda qisqa chegara ISHLAYOTGAN tikishni uzib qo\'yadi',
    );
    // Lekin cheksiz ham emas — foydalanuvchi shu ekranda kutib turibdi.
    expect(
      PanoCaptureFlowState.kStitchTimeout.inMinutes,
      lessThanOrEqualTo(10),
    );
  });

  test('timeout matni uch tilda bor va XOM KALIT emas', () {
    for (final l in const [Locale('uz'), Locale('ru'), Locale('en')]) {
      final t = tr(l, 'bozor.pano.flow.timeout');
      expect(t, isNot('bozor.pano.flow.timeout'),
          reason: '${l.languageCode}: tarjima yo\'q');
      expect(t, isNotEmpty);
    }
  });

  testWidgets('server `queued` da qotib qolsa — ekran XATO ko\'rsatadi',
      (tester) async {
    var statusCalls = 0;
    final client = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/listings/pano')) {
        return http.Response('{"id":1,"status":"capturing"}', 201);
      }
      if (p.endsWith('/finish')) {
        return http.Response('{"id":1,"status":"queued"}', 200);
      }
      // Server HECH QACHON oldinga siljimaydi — worker yo'q.
      statusCalls++;
      return http.Response(
        '{"id":1,"status":"queued","progress":0}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uz'),
        // ⚠️ `supportedLocales` SIZ `Localizations.localeOf` inglizchaga
        // tushib qoladi (sukut `en_US`) va test o'zbekcha matnni topolmaydi
        // — ekran to'g'ri ishlayotgan bo'lsa ham. Bir marta shunday bo'ldi.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
        home: PanoCaptureFlow(api: PanoApi(client: client)),
      ),
    );
    await tester.pump();

    final state = tester.state<PanoCaptureFlowState>(
      find.byType(PanoCaptureFlow),
    );
    // Nativ capture testda yo'q — to'g'ridan «tikilmoqda» bosqichiga qo'yamiz.
    state.debugEnterStitching(1);
    await tester.pump();

    // Chegaradan OLDIN hali kutadi.
    await tester.pump(PanoCaptureFlowState.kStitchTimeout ~/ 2);
    expect(find.text(tr(const Locale('uz'), 'bozor.pano.flow.failed')),
        findsNothing);
    expect(statusCalls, greaterThan(0), reason: 'polling boshlanmadi');

    // Chegaradan keyin — xato va «Qayta urinish».
    await tester.pump(PanoCaptureFlowState.kStitchTimeout);
    await tester.pump();

    expect(find.text(tr(const Locale('uz'), 'bozor.pano.flow.failed')),
        findsOneWidget);
    expect(find.text(tr(const Locale('uz'), 'bozor.pano.flow.timeout')),
        findsOneWidget);
    expect(find.text(tr(const Locale('uz'), 'bozor.pano.flow.retry')),
        findsOneWidget);
  });
}
