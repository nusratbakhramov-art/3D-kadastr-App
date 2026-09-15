/// Geoportal (open.ngis.uz) kadastr qatlamlarini o'qish.
///
/// Ikkita javob formati tekshiriladi:
/// - ko'rinish so'rovi — `f=geojson` (`FeatureServer/<n>/query`);
/// - nuqta so'rovi — ArcGIS `f=json`, `features[].attributes` va `rings`.
///
/// Namunalar `db.ngis.uz` ning jonli javobidan olingan (Sirg'ali tumani,
/// 10:06:44:02:02:0514).
library;

import 'dart:convert';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/services/data/ngis_parcel_client.dart';
import 'package:latlong2/latlong.dart';

/// Bitta uchastka — turar-joy qatlamining jonli javobi (qisqartirilgan).
String _turar(String number) => jsonEncode({
      'features': [
        {
          'attributes': {
            'cadastral_number': number,
            'property_kind': 'prop_kind_private_house',
            'region_name': 'Toshkent shahri',
            'district_name': 'Sirg‘ali tumani',
            'mahalla_name': "Ko'hna Qumariq MFY",
          },
          'geometry': {
            'rings': [
              [
                [69.2575, 41.2402],
                [69.2578, 41.2404],
                [69.2576, 41.2400],
                [69.2575, 41.2402],
              ],
            ],
          },
        },
      ],
    });

String get _empty => jsonEncode({'features': <Object>[]});

/// Har bir qatlam uchun alohida javob beradigan mock.
///
/// Kalit — servis nomi BOSHIDAGI SLESH bilan (`/TURAR_UZKAD`): `TURAR_UZKAD`
/// `NOTURAR_UZKAD` ning ichida ham bor, sleshsiz moslashtirilsa noturar
/// so'rovi turar javobini olardi.
MockClient _clientFor(
  Map<String, String> bodyByService, {
  Set<String>? fail,
  List<http.Request>? log,
}) {
  return MockClient((req) async {
    log?.add(req);
    for (final entry in bodyByService.entries) {
      if (req.url.path.contains(entry.key)) {
        if (fail?.contains(entry.key) ?? false) {
          return http.Response('nope', 500);
        }
        return http.Response(entry.value, 200, headers: {
          'content-type': 'application/json; charset=utf-8',
        });
      }
    }
    return http.Response(_empty, 200);
  });
}

NgisLayer _layer(String id) =>
    kNgisParcelLayers.firstWhere((l) => l.id == id);

void main() {
  const point = LatLng(41.2402, 69.2573);
  final bounds = LatLngBounds(
    const LatLng(41.23, 69.25),
    const LatLng(41.24, 69.26),
  );

  group('ko\'rinish bo\'yicha (GeoJSON)', () {
    test('poligonni atributlari bilan o\'qiydi', () async {
      final client = NgisParcelClient(
        client: _clientFor({
          '/TURAR_UZKAD': jsonEncode({
            'type': 'FeatureCollection',
            'features': [
              {
                'type': 'Feature',
                'properties': {
                  'cadastral_number': '10:06:44:02:02:0514',
                  'region_name': 'Toshkent shahri',
                  'district_name': 'Sirg‘ali tumani',
                  'mahalla_name': "Ko'hna Qumariq MFY",
                },
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [
                      [69.2575, 41.2402],
                      [69.2578, 41.2404],
                      [69.2576, 41.2400],
                      [69.2575, 41.2402],
                    ],
                  ],
                },
              },
            ],
          }),
        }),
      );

      final found =
          await client.parcelsInBounds(_layer('turar'), bounds);

      expect(found, hasLength(1));
      final p = found.single;
      expect(p.cadastreNumber, '10:06:44:02:02:0514');
      expect(p.layerId, 'turar');
      expect(p.placeLabel,
          "Toshkent shahri, Sirg‘ali tumani, Ko'hna Qumariq MFY");
      // GeoJSON tartibi [lng, lat] — teskarisiga o'girilishi shart.
      expect(p.outline.first.longitude, closeTo(69.2575, 1e-6));
      expect(p.outline.first.latitude, closeTo(41.2402, 1e-6));
    });

    test('bo\'lingan uchastka (MultiPolygon) hamma bo\'lagi bilan keladi',
        () async {
      final client = NgisParcelClient(
        client: _clientFor({
          '/DKYAT_2023': jsonEncode({
            'features': [
              {
                'properties': {'kadastr': '10:06:05:02:01:5228'},
                'geometry': {
                  'type': 'MultiPolygon',
                  'coordinates': [
                    [
                      [
                        [69.25, 41.24],
                        [69.251, 41.241],
                        [69.252, 41.24],
                        [69.25, 41.24],
                      ],
                    ],
                    [
                      [
                        [69.26, 41.25],
                        [69.261, 41.251],
                        [69.262, 41.25],
                        [69.263, 41.249],
                        [69.26, 41.25],
                      ],
                    ],
                  ],
                },
              },
            ],
          }),
        }),
      );

      final found =
          await client.parcelsInBounds(_layer('xatlovsiz'), bounds);

      expect(found.single.parts, hasLength(2));
      // `outline` — eng katta bo'lak (ajratib ko'rsatish uchun).
      expect(found.single.outline, hasLength(5));
    });

    test('so\'rov ko\'rinish chegarasini va qatlam maydonini uzatadi',
        () async {
      final log = <http.Request>[];
      final client = NgisParcelClient(client: _clientFor({}, log: log));

      await client.parcelsInBounds(_layer('xatlovsiz'), bounds);

      final req = log.single;
      // Bbox so'rovi FAQAT FeatureServer ga boradi: MapServer envelope bilan
      // bo'sh javob qaytaradi.
      expect(req.url.path, contains('/FeatureServer/0/query'));
      final body = Uri.splitQueryString(req.body);
      expect(body['geometry'], '69.25,41.23,69.26,41.24');
      expect(body['geometryType'], 'esriGeometryEnvelope');
      expect(body['f'], 'geojson');
      expect(body['returnGeometry'], 'true');
      // Xatlovsiz qatlamda raqam `kadastr` maydonida, joylashuv esa
      // viloyat/tuman da — boshqa qatlamlardagidan farq qiladi.
      expect(body['outFields'], 'kadastr,viloyat,tuman');
    });

    test('geometriyasiz yozuv chizishga tushmaydi', () async {
      final client = NgisParcelClient(
        client: _clientFor({
          '/TURAR_UZKAD': jsonEncode({
            'features': [
              {
                'properties': {'cadastral_number': '10:06:44:02:02:0514'},
                'geometry': null,
              },
            ],
          }),
        }),
      );

      expect(await client.parcelsInBounds(_layer('turar'), bounds), isEmpty);
    });
  });

  group('nuqta bo\'yicha (zaxira yo\'l)', () {
    test('nuqtadagi uchastkani atributlari bilan qaytaradi', () async {
      final client = NgisParcelClient(
        client: _clientFor({'/TURAR_UZKAD': _turar('10:06:44:02:02:0514')}),
      );

      final found = await client.identifyAt(point);

      expect(found, hasLength(1));
      final p = found.single;
      expect(p.cadastreNumber, '10:06:44:02:02:0514');
      expect(p.layerId, 'turar');
      expect(p.placeLabel,
          "Toshkent shahri, Sirg‘ali tumani, Ko'hna Qumariq MFY");
      expect(p.outline.first.longitude, closeTo(69.2575, 1e-6));
      expect(p.outline.first.latitude, closeTo(41.2402, 1e-6));
      expect(p.center, isNotNull);
    });

    test('ustma-ust tushgan uchastkalar HAMMASI qaytadi, qatlam tartibida',
        () async {
      // Geoportalning o'zi ham bir nuqtada bir nechta obyektni `1/3` bilan
      // ko'rsatadi — tanlashni foydalanuvchi qiladi, biz birontasini
      // o'zboshimchalik bilan tashlab yubormaymiz.
      final client = NgisParcelClient(
        client: _clientFor({
          '/TURAR_UZKAD': _turar('10:06:44:02:02:0479/0001'),
          '/NOTURAR_UZKAD': _turar('10:06:44:02:02:0496'),
          '/DKYAT_2023': jsonEncode({
            'features': [
              {
                'attributes': {'kadastr': '10:06:05:02:01:5228'},
              },
            ],
          }),
        }),
      );

      final found = await client.identifyAt(point);

      expect(
        found.map((p) => p.cadastreNumber),
        [
          '10:06:44:02:02:0479/0001',
          '10:06:44:02:02:0496',
          '10:06:05:02:01:5228',
        ],
      );
      expect(found.map((p) => p.layerId), ['turar', 'noturar', 'xatlovsiz']);
    });

    test('bir raqam ikki qatlamda uchrasa bir marta qaytadi', () async {
      final client = NgisParcelClient(
        client: _clientFor({
          '/TURAR_UZKAD': _turar('10:06:44:02:02:0514'),
          '/NOTURAR_UZKAD': _turar('10:06:44:02:02:0514'),
        }),
      );

      final found = await client.identifyAt(point);

      expect(found, hasLength(1));
      expect(found.single.layerId, 'turar'); // ustuvorroq qatlam qoladi
    });

    test('bitta qatlam yiqilsa qolganlari baribir qaytadi', () async {
      final client = NgisParcelClient(
        client: _clientFor(
          {
            '/TURAR_UZKAD': _turar('10:06:44:02:02:0514'),
            '/NOTURAR_UZKAD': _turar('10:06:44:02:02:0496'),
          },
          fail: {'/NOTURAR_UZKAD'},
        ),
      );

      final found = await client.identifyAt(point);

      expect(found.map((p) => p.cadastreNumber), ['10:06:44:02:02:0514']);
    });

    test('ArcGIS xatoni 200 bilan qaytarsa ham natija sifatida olinmaydi',
        () async {
      // ArcGIS `error` ni HTTP 200 ichida beradi — statusga qarab bo'lmaydi.
      final client = NgisParcelClient(
        client: _clientFor({
          '/TURAR_UZKAD': jsonEncode({
            'error': {'code': 400, 'message': 'Unable to complete operation'},
          }),
        }),
      );

      expect(await client.identifyAt(point), isEmpty);
    });

    test('raqamsiz yozuv tashlab yuboriladi', () async {
      final client = NgisParcelClient(
        client: _clientFor({
          '/TURAR_UZKAD': jsonEncode({
            'features': [
              {
                'attributes': {'cadastral_number': '   '},
              },
            ],
          }),
        }),
      );

      expect(await client.identifyAt(point), isEmpty);
    });
  });

  group('qatlam chegaralari', () {
    test('masshtab zoomga o\'giriladi', () {
      // ArcGIS 1:5198 ≈ zoom 16.7 — geoportalda turar-joy uchastkalari aynan
      // shu masshtabda paydo bo'ladi.
      expect(scaleToZoom(5198.278858), closeTo(16.71, 0.01));
      expect(scaleToZoom(0), 0);
    });

    test('chizish tartibi aniqdan umumiyga qarab kelmaydi', () {
      // Ro'yxat ustma-ust chizilish tartibida: oxirgisi eng ustida bo'lishi
      // kerak, chunki bosilganda birinchi bo'lib o'sha taklif qilinadi.
      expect(kNgisParcelLayers.last.id, 'turar');
      expect(kNgisParcelLayers.first.id, 'qishloq');
      expect(kNgisIdentifyOrder.first.id, 'turar');
    });

    test('uchastka tengligi raqam va qatlam bo\'yicha', () {
      // `PolygonLayer` bo'lingan uchastkaning har bir bo'lagini alohida
      // poligon qilib chizadi — bosilganda ular bitta obyekt bo'lib qaytadi.
      const a = NgisParcel(cadastreNumber: '10:06', layerId: 'turar');
      const b = NgisParcel(cadastreNumber: '10:06', layerId: 'turar');
      const c = NgisParcel(cadastreNumber: '10:06', layerId: 'noturar');
      expect(a, b);
      expect(a, isNot(c));
      expect({...[a, b, c]}, hasLength(2));
    });
  });
}
