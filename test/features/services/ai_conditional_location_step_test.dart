import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/api_cadastre_service.dart';
import 'package:kadastr/features/services/models/ai_baholash_bundle.dart';
import 'package:kadastr/features/services/models/ai_wizard_steps.dart';

/// «Joylashuv» qadami SHARTLI (D-vazifa).
///
/// Mijozning shikoyati: foydalanuvchi obyektni geoportal xaritasida
/// ko'rsatadi, reyestr ma'lumoti chiqadi — va keyin ilova o'sha uyni YANA
/// bir marta xaritada belgilashni so'raydi.
///
/// ⚠️ QAROR KOORDINATAGA QARAB EMAS. `location != null` yetarli emas:
/// Toshkent sukuti ham, qurilma GPS'i ham koordinata. Shuning uchun
/// [AiBaholashBundle.locationSource] — MANBA — hal qiladi.
void main() {
  AiBaholashBundle bundle() => AiBaholashBundle(
    kadastr: const CadastreLookupResult(
      cadastreNumber: '10:10:42:03:02:0098',
      address: 'Toshkent shahri, Shayxontohur tumani',
      totalArea: 8334,
    ),
  );

  const somewhere = AiLocationInfo(lat: 41.310071, lng: 69.239068);

  group('CASE 1 — uchastka xaritada tanlandi, reyestr topildi', () {
    test('qo\'lda xarita qadami KERAK EMAS', () {
      final b = bundle()
        ..parcelCenter = const AiParcelPoint(
          lat: 41.310071,
          lng: 69.239068,
          cadastreNumber: '10:10:42:03:02:0098',
        )
        ..location = somewhere
        ..locationSource = AiLocationSource.parcel;

      expect(b.needsManualLocation, isFalse);
      expect(b.aiSteps, isNot(contains(AiStep.location)));
    });

    test('progress chizig\'i 6 bo\'lak bo\'ladi, 7 emas', () {
      final b = bundle()..locationSource = AiLocationSource.parcel;
      expect(b.aiStepCount, 6);
      // Keyingi qadamlar indeksi ham suriladi — chiziq oxirida to'ladi.
      expect(b.aiStepIndex(AiStep.purpose), 2);
      expect(b.aiStepIndex(AiStep.targetPrice), 5);
    });
  });

  group('CASE 2 — reyestr ishonchli nuqta berdi', () {
    test('qo\'lda xarita qadami KERAK EMAS', () {
      final b = bundle()
        ..location = somewhere
        ..locationSource = AiLocationSource.cadastreLookup;
      expect(b.needsManualLocation, isFalse);
      expect(b.aiSteps, isNot(contains(AiStep.location)));
    });
  });

  group('CASE 3 — raqam qo\'lda kiritildi, nuqta yo\'q', () {
    test('qo\'lda xarita qadami KO\'RSATILADI', () {
      final b = bundle();
      expect(b.locationSource, AiLocationSource.none);
      expect(b.needsManualLocation, isTrue);
      expect(b.aiSteps, contains(AiStep.location));
      expect(b.aiStepCount, 7);
      expect(b.aiStepIndex(AiStep.location), 2);
    });
  });

  group('CASE 7 — «hujjat bilan davom etish»', () {
    test('holat yoziladi va hujjat talab qilinadi', () {
      final b = bundle()
        ..cadastreResolution = AiCadastreResolution.documentRequired;
      expect(b.needsCadastreDocument, isTrue);
    });

    test('nuqta noma\'lumligicha qolgani uchun xarita qadami chiqadi', () {
      final b = bundle()
        ..cadastreResolution = AiCadastreResolution.documentRequired;
      expect(b.needsManualLocation, isTrue);
      expect(b.aiSteps, contains(AiStep.location));
    });

    test('holat qoralamada SAQLANADI va tiklanadi', () {
      final b = bundle()
        ..cadastreResolution = AiCadastreResolution.documentRequired
        ..locationSource = AiLocationSource.manualMap
        ..location = somewhere;

      final draft = b.toJson(forDraft: true);
      expect(draft['cadastre_resolution'], 'document_required');
      expect(draft['location_source'], 'manual_map');

      final back = AiBaholashBundle.fromJson(draft);
      expect(back.needsCadastreDocument, isTrue);
      expect(back.locationSource, AiLocationSource.manualMap);
      expect(back.needsManualLocation, isFalse);
    });

    test('yaratish so\'roviga bu maydonlar QO\'SHILMAYDI', () {
      final b = bundle()
        ..cadastreResolution = AiCadastreResolution.documentRequired
        ..locationSource = AiLocationSource.manualMap;
      final wire = b.toJson();
      expect(wire.containsKey('cadastre_resolution'), isFalse);
      expect(wire.containsKey('location_source'), isFalse);
    });
  });

  group('CASE 8 — qurilma GPS\'i obyekt joyi EMAS', () {
    test('GPS manbalar ro\'yxatida umuman yo\'q', () {
      // Ro'yxatda faqat to'rtta manba bor va ularning hech biri qurilma
      // joylashuvi emas. «Mening joylashuvim» tugmasi bosilib, pin
      // TASDIQLANSA — bu `manualMap`, ya'ni foydalanuvchining ongli tanlovi.
      expect(AiLocationSource.values, hasLength(4));
      expect(
        AiLocationSource.values.map((e) => e.wire),
        containsAll(<String>['none', 'parcel', 'cadastre_lookup', 'manual_map']),
      );
    });

    test('uchastka tanlangach manba o\'zgarmaydi', () {
      final b = bundle()
        ..locationSource = AiLocationSource.parcel
        ..location = somewhere;
      // Qoralamaga yozib, qayta o'qiymiz — manba «parcel» bo'lib qoladi.
      final back = AiBaholashBundle.fromJson(b.toJson(forDraft: true));
      expect(back.locationSource, AiLocationSource.parcel);
      expect(back.needsManualLocation, isFalse);
    });
  });

  group('holat nomlari WIRE da barqaror', () {
    test('noma\'lum qiymat xavfsiz sukutga tushadi', () {
      expect(AiLocationSource.fromWire('nonsense'), AiLocationSource.none);
      expect(AiLocationSource.fromWire(null), AiLocationSource.none);
      expect(
        AiCadastreResolution.fromWire('nonsense'),
        AiCadastreResolution.resolved,
      );
    });
  });
}
