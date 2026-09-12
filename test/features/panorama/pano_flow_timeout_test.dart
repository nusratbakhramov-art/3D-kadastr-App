import 'dart:async';
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

  test('kStitchTimeout PRODDA o\'lchangan vaqtdan katta', () {
    // ⚠️ 2026-09-12, prod `celery-panorama` logi (28 kadr → 4096×2048):
    //     420.5 s · 451.2 s · 459.4 s · 474.1 s
    // Ilgari bu yerda 6 daqiqa turardi — ishlab chiqish mashinasidagi
    // 32 s o'lchoviga tayanib. Prodda muddat ish TUGASHIDAN OLDIN otildi
    // va TAYYOR panorama tashlab yuborildi.
    const worstMeasured = 475;
    expect(
      PanoCaptureFlowState.kStitchTimeout.inSeconds,
      greaterThanOrEqualTo(worstMeasured * 2),
      reason: 'ishlayotgan tikishni uzib qo\'yadi — prodda shunday bo\'lgan',
    );
    // Lekin cheksiz ham emas — foydalanuvchi shu ekranda kutib turibdi.
    expect(
      PanoCaptureFlowState.kStitchTimeout.inMinutes,
      lessThanOrEqualTo(30),
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

  testWidgets('muddatdan keyin «Qayta urinish» TAYYOR ishni oladi — '
      'kadrlarni QAYTA YUBORMAYDI', (tester) async {
    // ⚠️ 2026-09-12 da prodda aynan shu yo'qotildi: ilova 6-daqiqada voz
    // kechdi, server esa 7.9-daqiqada panoramani tayyorlab S3 ga yukladi.
    // Eski `_retry` YANGI ish yaratardi — tayyor panorama tashlanib,
    // foydalanuvchi yana sakkiz daqiqa kutardi.
    var done = false;
    var uploads = 0;
    final client = MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/listings/pano')) {
        uploads++;
        return http.Response('{"id":7,"status":"capturing"}', 201);
      }
      final body = done
          ? '{"id":7,"status":"done","progress":1,'
              '"storage_key":"listings/media/1/pano_7.jpg",'
              '"url":"https://cdn.test/pano_7.jpg"}'
          : '{"id":7,"status":"stitching","progress":0.4}';
      return http.Response(body, 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    // ⚠️ Oqim OSTIDA sahifa bo'lishi shart: `Navigator.pop` yagona
    // marshrutni yopmaydi, ya'ni oqim o'zi root bo'lsa natija hech qachon
    // qaytmaydi va test yolg'on yiqiladi (bir marta shunday bo'ldi).
    PanoOutcome? popped;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
        home: const Scaffold(body: Text('ortda')),
      ),
    );
    final ctx = tester.element(find.text('ortda'));
    unawaited(
      Navigator.of(ctx)
          .push<PanoOutcome>(
            MaterialPageRoute<PanoOutcome>(
              builder: (_) => PanoCaptureFlow(api: PanoApi(client: client)),
            ),
          )
          .then((v) => popped = v),
    );
    // ⚠️ `pumpAndSettle` ISHLATILMAYDI: ekranda cheksiz aylanadigan
    // `CircularProgressIndicator` bor, ya'ni kadr rejasi hech qachon
    // bo'shamaydi va `pumpAndSettle` timeout bilan yiqiladi.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final state = tester.state<PanoCaptureFlowState>(
      find.byType(PanoCaptureFlow),
    );
    state.debugEnterStitching(7);
    await tester.pump();

    // Muddat otiladi — ekran xato ko'rsatadi.
    await tester.pump(PanoCaptureFlowState.kStitchTimeout);
    await tester.pump();
    expect(find.text(tr(const Locale('uz'), 'bozor.pano.flow.failed')),
        findsOneWidget);

    // Shu orada server ishni YAKUNLADI.
    done = true;

    await tester.tap(find.text(tr(const Locale('uz'), 'bozor.pano.flow.retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(uploads, 0,
        reason: 'yangi ish yaratilmasin — tayyorini olish kerak edi');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PanoCaptureFlow), findsNothing,
        reason: 'natija bilan yopilishi kerak edi');
    expect(popped, isNotNull, reason: 'natija qaytmadi');
    expect(popped!.storageKey, 'listings/media/1/pano_7.jpg');
    expect(popped!.url, 'https://cdn.test/pano_7.jpg');
  });
}
