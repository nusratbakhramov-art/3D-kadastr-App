// Uchastka chegarasining sim ustidagi shakli.
//
// Nega bu testlar bor. GeoJSON nuqtasi `[lng, lat]`, `LatLng` esa
// `(lat, lng)` — TESKARI. Almashtirib yuborish kompilyatsiyada ham,
// tekshiruvda ham ushlanmaydi (ikkalasi ham double), xato esa JIMGINA
// bo'ladi: e'lon chegarasi Toshkent o'rniga Hind okeanida chiziladi va buni
// faqat e'lonni ochgan xaridor ko'radi.
//
// Ikkinchi qo'riqlanadigan narsa — nuqtalar soni: backend 4000 tadan
// ko'pini 422 bilan rad etadi, ya'ni kesish KLIENTDA bo'lishi shart, aks
// holda yirik uchastkali e'lon yuborilmay qoladi va foydalanuvchi buni
// tuzata olmaydi.
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/models/parcel_boundary.dart';
import 'package:latlong2/latlong.dart';

/// Toshkentdagi kichik to'rtburchak.
const _ring = [
  LatLng(41.311081, 69.240562),
  LatLng(41.311081, 69.240800),
  LatLng(41.311300, 69.240800),
  LatLng(41.311300, 69.240562),
];

void main() {
  group('toGeoJson', () {
    test('nuqta [lng, lat] tartibida yoziladi', () {
      final json = ParcelBoundary.fromRings([_ring])!.toGeoJson();
      final first =
          (json['coordinates'] as List)[0][0][0] as List<dynamic>;
      // Uzunlik (69.x) OLDIN, kenglik (41.x) keyin.
      expect(first[0], closeTo(69.240562, 1e-9));
      expect(first[1], closeTo(41.311081, 1e-9));
    });

    test('shakl MultiPolygon va har bo\'lak bitta halqa', () {
      final json = ParcelBoundary.fromRings([_ring, _ring])!.toGeoJson();
      expect(json['type'], 'MultiPolygon');
      final parts = json['coordinates'] as List;
      expect(parts, hasLength(2));
      expect(parts[0], hasLength(1)); // ichki teshik yo'q
    });

    test('halqa OCHIQ yuboriladi — yopishni backend bajaradi', () {
      // Ikkala tomon ham yopsa halqa ikki marta yopilardi; qoida BITTA
      // joyda (`_validate_boundary`) turishi kerak.
      final json = ParcelBoundary.fromRings([_ring])!.toGeoJson();
      final ring = (json['coordinates'] as List)[0][0] as List;
      expect(ring, hasLength(_ring.length));
    });
  });

  group('fromGeoJson', () {
    test('to\'liq aylanma: yozilgan narsa aynan o\'qiladi', () {
      final json = ParcelBoundary.fromRings([_ring])!.toGeoJson();
      final back = ParcelBoundary.fromGeoJson(json)!;
      expect(back.parts.single, hasLength(_ring.length));
      for (var i = 0; i < _ring.length; i++) {
        expect(back.parts.single[i].latitude, closeTo(_ring[i].latitude, 1e-9));
        expect(
          back.parts.single[i].longitude,
          closeTo(_ring[i].longitude, 1e-9),
        );
      }
    });

    test('backend yopib qaytargan halqa ham o\'qiladi', () {
      final closed = [
        [
          [
            for (final p in _ring) [p.longitude, p.latitude],
            [_ring.first.longitude, _ring.first.latitude],
          ],
        ],
      ];
      final back = ParcelBoundary.fromGeoJson({
        'type': 'MultiPolygon',
        'coordinates': closed,
      })!;
      expect(back.parts.single, hasLength(_ring.length + 1));
    });

    test('buzilgan yoki notanish shakl null beradi, yiqilmaydi', () {
      // E'lon sahifasi chegarasiz ochilaveradi — bu xato butun sahifani
      // yiqitmasligi kerak.
      for (final bad in <Object?>[
        null,
        'MultiPolygon',
        <String, Object?>{'type': 'Polygon', 'coordinates': []},
        <String, Object?>{'type': 'MultiPolygon'},
        <String, Object?>{'type': 'MultiPolygon', 'coordinates': 'x'},
        // Halqada atigi ikki nuqta — yuza emas.
        <String, Object?>{
          'type': 'MultiPolygon',
          'coordinates': [
            [
              [
                [69.24, 41.31],
                [69.25, 41.31],
              ],
            ],
          ],
        },
      ]) {
        expect(ParcelBoundary.fromGeoJson(bad), isNull, reason: '$bad');
      }
    });
  });

  group('fromRings', () {
    test('uchtadan kam nuqtali halqa tashlanadi', () {
      expect(ParcelBoundary.fromRings([_ring.take(2).toList()]), isNull);
    });

    test('yaroqli va yaroqsiz halqa aralash bo\'lsa yaroqlisi qoladi', () {
      final b = ParcelBoundary.fromRings([_ring.take(2).toList(), _ring])!;
      expect(b.parts, hasLength(1));
    });

    test('bo\'sh ro\'yxat null beradi', () {
      expect(ParcelBoundary.fromRings(const []), isNull);
    });
  });

  group('nuqtalar soni chegarasi', () {
    List<LatLng> hugeRing(int n) => [
      for (var i = 0; i < n; i++) LatLng(41.31 + i * 1e-7, 69.24 + i * 1e-7),
    ];

    test('chegaradan oshgan halqa siyraklashtiriladi', () {
      final b = ParcelBoundary.fromRings([hugeRing(9000)])!;
      expect(b.pointCount, lessThanOrEqualTo(ParcelBoundary.maxPoints));
      // Shakl saqlanadi — uchburchakka tushib qolmaydi.
      expect(b.pointCount, greaterThan(1000));
    });

    test('bir necha bo\'lak birgalikda ham chegaradan oshmaydi', () {
      final b = ParcelBoundary.fromRings([
        hugeRing(3000),
        hugeRing(3000),
        hugeRing(3000),
      ])!;
      expect(b.pointCount, lessThanOrEqualTo(ParcelBoundary.maxPoints));
      expect(b.parts, hasLength(3));
    });

    test('chegaradan kichik chegara tegilmaydi', () {
      final b = ParcelBoundary.fromRings([_ring])!;
      expect(b.pointCount, _ring.length);
    });
  });

  test('center — eng katta bo\'lakning o\'rtasi', () {
    final b = ParcelBoundary.fromRings([_ring])!;
    expect(b.center!.latitude, closeTo(41.3111905, 1e-6));
    expect(b.center!.longitude, closeTo(69.240681, 1e-6));
  });
}
