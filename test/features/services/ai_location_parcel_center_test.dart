import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/api_cadastre_service.dart';
import 'package:kadastr/features/services/models/ai_baholash_bundle.dart';
import 'package:kadastr/features/services/screens/ai_location_screen.dart';

/// Joylashuv qadami GEOPORTALDA tanlangan uchastka markazidan boshlanadi
/// (VAL-05), va TEGILMAGAN sukut nuqtasi hech qachon obyektning joylashuvi
/// sifatida saqlanmaydi.
///
/// ⚠️ NEGA. Ilgari bu qadam pinni kadastr MANZILI matnini geokodlab qo'yardi.
/// Manzil topilmasa pin Toshkent markazida qolar, reverse-geokod esa o'sha
/// markazning matnini yozib qo'yardi — va «haqiqiy joy tanlandimi» sharti
/// (matn bor) bajarilib, SUKUT nuqtasi arizaga tushardi. Foydalanuvchi esa
/// obyektni 1-qadamda xaritada allaqachon ko'rsatgan bo'lardi.
///
/// Qurilmaning GPS joylashuvi bu yerda umuman qatnashmaydi: u faqat «mening
/// joylashuvim» tugmasi bosilganda o'qiladi.
void main() {
  const parcelLat = 40.7821;
  const parcelLng = 72.3442; // Farg'ona — Toshkent sukutidan uzoq.
  const tashkentDefaultLat = 41.2995;

  AiBaholashBundle bundle({AiParcelPoint? parcel}) => AiBaholashBundle(
    kadastr: const CadastreLookupResult(
      cadastreNumber: '10:01:01:01:01:0001',
      // Manzil ATAYLAB bor: geokod yo'li ishlab ketmasligini ham ko'ramiz.
      address: 'Farg\'ona viloyati, Quva tumani, Bog\' MFY, 7-uy',
    ),
  )..parcelCenter = parcel;

  /// Xarita PLITKALARINI yuklashdagi xatolarni yutadi.
  ///
  /// ⚠️ `flutter_test` hamma HTTP so'roviga 400 qaytaradi, `flutter_map` esa
  /// har bir plitka uchun `ClientException` chiqaradi (bitta kadrda 20+ ta).
  /// Bu sinov muhitining xossasi — tekshirilayotgan narsa pin QAYERDA
  /// turgani, plitka rasmlari emas. Boshqa xatolar avvalgidek yiqitadi.
  void ignoreTileLoadErrors() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exception.toString();
      if (text.contains('ClientException') || text.contains('status 400')) {
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  Future<void> pumpAndDispose(WidgetTester tester, AiBaholashBundle b) async {
    ignoreTileLoadErrors();
    await tester.pumpWidget(MaterialApp(home: AiLocationScreen(bundle: b)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // Ekrandan chiqish — `dispose` tanlangan joyni bundle'ga yozadi.
    await tester.pumpWidget(const SizedBox());
    // Geokoder so'rovlari 12-20 s taymer qo'yadi; `flutter_test` ochiq taymer
    // bilan tugashga yo'l qo'ymaydi, shuning uchun ularni oxirigacha suramiz.
    await tester.pump(const Duration(seconds: 60));
  }

  testWidgets('uchastka markazi bo\'lsa — AYNAN o\'sha nuqta saqlanadi', (
    tester,
  ) async {
    final b = bundle(
      parcel: const AiParcelPoint(
        lat: parcelLat,
        lng: parcelLng,
        cadastreNumber: '10:01:01:01:01:0001',
      ),
    );
    await pumpAndDispose(tester, b);

    expect(b.location, isNotNull);
    expect(b.location!.lat, closeTo(parcelLat, 0.0001));
    expect(b.location!.lng, closeTo(parcelLng, 0.0001));
  });

  testWidgets('uchastka ham, geokod ham yo\'q — sukut nuqtasi SAQLANMAYDI', (
    tester,
  ) async {
    final b = bundle();
    await pumpAndDispose(tester, b);

    expect(
      b.location?.lat,
      isNot(closeTo(tashkentDefaultLat, 0.0001)),
      reason: 'tegilmagan Toshkent sukuti obyektning joylashuvi emas',
    );
  });

  testWidgets('uchastka markazi bundle draft payloadida ketadi', (
    tester,
  ) async {
    final b = bundle(
      parcel: const AiParcelPoint(lat: parcelLat, lng: parcelLng),
    );

    expect(
      b.toJson()['parcel_center'],
      isNull,
      reason: 'yaratish so\'roviga e\'lon qilinmagan maydon qo\'shilmaydi',
    );
    expect(
      (b.toJson(forDraft: true)['parcel_center'] as Map?)?['lat'],
      parcelLat,
      reason: 'qoralamada saqlanadi — resume\'da pin joyida qolsin',
    );
  });
}
