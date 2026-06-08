import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/models/calculator_draft.dart';
import 'package:kadastr/features/services/models/calculator_pricing.dart';

void main() {
  const uz = Locale('uz');
  final pricing = CalculatorPricing.defaults;

  group('compute* default pricing — TZ hujjat misollariga mos', () {
    test('arxitektura 555 m² × rekonstruksiya = 39 960 000', () {
      final r = computeArxitektura(
        objectType: ArxitekturaObject.rekonstruksiya,
        areaM2: 555,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 39960000);
    });

    test('kadastr yakka 555 m² (500–1000 pog\'ona) = 14 900 000', () {
      final r = computeKadastr(
        objectType: KadastrObjectType.yakka,
        areaM2: 555,
        is3d: false,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 14900000);
    });

    test('3D kadastr yakka 555 m² = 30 800 000', () {
      final r = computeKadastr(
        objectType: KadastrObjectType.yakka,
        areaM2: 555,
        is3d: true,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 30800000);
    });

    test('kadastr xonadon = belgilangan 4 900 000 (maydonga bog\'liq emas)', () {
      final r = computeKadastr(
        objectType: KadastrObjectType.xonadon,
        areaM2: 999,
        is3d: false,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 4900000);
    });

    test('kadastr ko\'p kvartirali 1000 m² × 7500 = 7 500 000', () {
      final r = computeKadastr(
        objectType: KadastrObjectType.kopKvartirali,
        areaM2: 1000,
        is3d: false,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 7500000);
    });

    test('baholash tugallanmagan 555 × 15000 = 8 325 000', () {
      final r = computeBaholash(
        objectType: BaholashObject.tugallanmagan,
        areaM2: 555,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 8325000);
    });

    test('baholash uy-joy ≤200 m² → belgilangan 490 000', () {
      final r = computeBaholash(
        objectType: BaholashObject.uyJoy,
        areaM2: 150,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 490000);
    });

    test('baholash uy-joy >200 m² → 6000 × maydon', () {
      final r = computeBaholash(
        objectType: BaholashObject.uyJoy,
        areaM2: 300,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 1800000);
    });

    test('dizayn 555 × 130000 = 72 150 000', () {
      final r = computeDizayn(
        objectType: DizaynObjectType.turar,
        style: DizaynStyle.loft,
        areaM2: 555,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 72150000);
    });

    test('dizayn ≤100 m² → 180000/m²', () {
      final r = computeDizayn(
        objectType: DizaynObjectType.turar,
        style: DizaynStyle.loft,
        areaM2: 100,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 18000000);
    });

    test('ta\'mirlash tamir 555 × 5 000 000 = 2 775 000 000', () {
      final r = computeTamirlash(
        objectType: TamirlashObjectType.turar,
        location: TamirlashLocation.toshkentShahar,
        serviceType: TamirlashServiceType.tamir,
        areaM2: 555,
        pricing: pricing,
        locale: uz,
      );
      expect(r.totalUzs, 2775000000);
    });
  });

  group('CalculatorPricing JSON + adminka override', () {
    test('fromJson rates + yuridik ni o\'qiydi', () {
      final p = CalculatorPricing.fromJson({
        'version': '2026-06-02T00:00:00Z',
        'rates': {'arxitektura.rekonstruksiya': 80000},
        'yuridik': [
          {
            'key': 'yuridik.maslahat',
            'value': {'uz': "999 so'm", 'ru': '999', 'en': '999'},
          },
        ],
      });
      expect(p.version, '2026-06-02T00:00:00Z');
      expect(p.rate('arxitektura.rekonstruksiya'), 80000);
      expect(p.yuridikValue('yuridik.maslahat', uz), "999 so'm");
    });

    test('yetishmagan kalit default qiymatga tushadi', () {
      final p = CalculatorPricing.fromJson({'rates': {}, 'yuridik': []});
      expect(p.rate('arxitektura.yakka_small'), 36000);
      expect(p.yuridikValue('yuridik.sud', uz), contains('20 000 000'));
    });

    test('adminka narxni o\'zgartirsa — natija ham o\'zgaradi', () {
      final p = CalculatorPricing.fromJson({
        'rates': {'arxitektura.rekonstruksiya': 80000},
        'yuridik': [],
      });
      final r = computeArxitektura(
        objectType: ArxitekturaObject.rekonstruksiya,
        areaM2: 555,
        pricing: p,
        locale: uz,
      );
      expect(r.totalUzs, 555 * 80000); // 44 400 000 — yangi narx aks etadi
    });
  });
}
