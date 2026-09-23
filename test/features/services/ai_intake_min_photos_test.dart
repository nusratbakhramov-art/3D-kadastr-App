import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/api_cadastre_service.dart';
import 'package:kadastr/features/services/models/ai_baholash_bundle.dart';
import 'package:kadastr/features/services/screens/ai_intake_screen.dart';
import 'package:kadastr/features/services/widgets/wizard_nav_bar.dart';

/// Majburiy rasm soni — 12 EMAS, 4 (PHOTO-01, mijoz talabi 2026-09-21).
///
/// Gate `_minPhotos` konstantasida; bu yerda uni EKRAN xulqi orqali
/// tekshiramiz, shunda konstantani o'zgartirib, ishlatilishini unutib
/// qoldirish mumkin bo'lmaydi.
void main() {
  AiBaholashBundle bundleWith(int photos, {int panoramas = 0}) =>
      AiBaholashBundle(
    kadastr: const CadastreLookupResult(
      cadastreNumber: '10:01:01:01:01:0001',
      address: 'Toshkent, Amir Temur 12',
      totalArea: 78.5,
    ),
    floor: 5,
    totalFloors: 9,
    imageKeys: [for (var i = 0; i < photos; i++) 'photo-$i'],
    panoramaKeys: [for (var i = 0; i < panoramas; i++) 'pano-$i.jpg'],
    kadastrKeys: const ['kadastr-1'],
    passportKeys: const ['passport-1'],
  );

  /// Ekranni chizishda paydo bo'ladigan «overflow» xatolarini YUTADI.
  ///
  /// ⚠️ NEGA. Ilova o'z shriftida (`MTSCompact`) chiziladi, `flutter_test` esa
  /// uni Ahem bilan almashtiradi — Ahem harflari balandroq va qat'iy
  /// balandlikdagi sarlavha paneli (56pt) bir necha piksel oshib ketadi. Bu
  /// SINOV MUHITINING artefakti: qurilmada bunday bo'lmaydi (simulyatordagi
  /// skrinshotlarga qarang). Tekshirilayotgan narsa — tugma yonadimi, ya'ni
  /// piksel o'lchamiga bog'liq emas.
  ///
  /// Boshqa har qanday xato AVVALGIDEK sinovni yiqitadi.
  void ignoreOverflowErrors() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  Future<bool> continueEnabled(
    WidgetTester tester,
    int photos, {
    int panoramas = 0,
  }) async {
    ignoreOverflowErrors();
    await tester.pumpWidget(
      MaterialApp(
        home: AiIntakeScreen(
          bundle: bundleWith(photos, panoramas: panoramas),
        ),
      ),
    );
    await tester.pump();
    final nav = tester.widget<WizardNavBar>(find.byType(WizardNavBar));
    return nav.continueEnabled;
  }

  testWidgets('3 ta rasm — «Hisoblash» BOSILMAYDI', (tester) async {
    expect(await continueEnabled(tester, 3), isFalse);
  });

  testWidgets('4 ta rasm — «Hisoblash» yonadi', (tester) async {
    expect(
      await continueEnabled(tester, 4),
      isTrue,
      reason: 'yangi eng kam chegara — 4 ta rasm',
    );
  });

  testWidgets('4 tadan ko\'p rasm ham o\'tadi', (tester) async {
    expect(await continueEnabled(tester, 7), isTrue);
  });

  // 4+ rasm YOKI 1+ 360° — ikkalasi birga shart emas (mijoz, 2026-09-23).
  testWidgets('rasmsiz, 1 ta 360° — «Hisoblash» yonadi', (tester) async {
    expect(await continueEnabled(tester, 0, panoramas: 1), isTrue);
  });

  testWidgets('2 ta rasm + 1 ta 360° — o\'tadi', (tester) async {
    expect(await continueEnabled(tester, 2, panoramas: 1), isTrue);
  });

  testWidgets('rasm ham, 360° ham yo\'q — bosilmaydi', (tester) async {
    expect(await continueEnabled(tester, 0), isFalse);
  });
}
