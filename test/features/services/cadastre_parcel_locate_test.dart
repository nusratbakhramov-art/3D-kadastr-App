/// Kadastr raqami bo'yicha uchastkani XARITADAN topish.
///
/// Mijozning ikki shikoyati shu yerda qotiriladi (2026-09-23):
///
/// 1. Raqam QO'LDA kiritilib «Qidirish» bosilganda reyestr ma'lumoti chiqardi,
///    lekin yuqoridagi xarita bo'sh qolardi — va keyingi qadamda ilova o'sha
///    uyni YANA xaritada belgilashni so'rardi. Reyestr javobida koordinata
///    yo'q, shuning uchun nuqta raqamning o'zidan, geoportaldan olinadi.
///
/// 2. Xaritadan tanlangan uy raqami `.../01` dumi bilan keladi — u vaqtda
///    hech qanday qidiruv boshlanmasdi (dum raqam shakliga tushmasdi), ya'ni
///    oqim boshi berk ko'chaga kirardi.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/services/cadastre_number.dart';
import 'package:kadastr/features/services/data/ngis_parcel_client.dart';

String _feature(String field, String number) => jsonEncode({
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'properties': {
        field: number,
        'region_name': 'Toshkent shahri',
        'district_name': 'Shayxontohur tumani',
        'mahalla_name': 'Kamolon MFY',
        'viloyat': 'Toshkent shahri',
        'tuman': 'Shayxontohur tumani',
      },
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [69.2400, 41.3100],
            [69.2402, 41.3102],
            [69.2404, 41.3100],
            [69.2400, 41.3100],
          ],
        ],
      },
    },
  ],
});

const _empty = '{"features":[]}';

/// So'ralgan `where` ga qarab javob beradigan mock.
///
/// Kalit — servis yo'lining bo'lagi va kutilgan `where` qiymati; ikkalasi ham
/// mos kelganda namuna qaytadi, aks holda bo'sh javob.
MockClient _client(
  List<({String service, String where, String body})> rules, {
  List<String>? log,
}) {
  return MockClient((req) async {
    final where = Uri.splitQueryString(req.body)['where'] ?? '';
    log?.add('${req.url.path}|$where');
    for (final r in rules) {
      if (req.url.path.contains(r.service) && where == r.where) {
        return http.Response(
          r.body,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    }
    return http.Response(_empty, 200);
  });
}

void main() {
  group('raqam shakli', () {
    test('xaritadan kelgan `/01` dumli raqam QABUL QILINADI', () {
      // Aynan shu tekshiruv «Qidirish» tugmasini chiqaradi va avtomatik
      // qidiruvni boshlaydi — rad etilganda oqim to'xtab qolardi.
      expect(isFullCadastreNumber('10:10:03:03:01:5414/01'), isTrue);
    });

    test('bo\'lingan uchastkaning `:` dumi ham qabul qilinadi', () {
      expect(isFullCadastreNumber('10:09:01:01:02:5942:0001:039'), isTrue);
    });

    test('chala raqam qabul qilinmaydi', () {
      expect(isFullCadastreNumber('10:10:03:03:02'), isFalse);
      expect(isFullCadastreNumber('10:10:03:03:02:579'), isFalse);
    });

    test('asos — dumsiz uchastka raqami', () {
      expect(cadastreBaseNumber('10:10:03:03:01:5414/01'), '10:10:03:03:01:5414');
      expect(
        cadastreBaseNumber('10:09:01:01:02:5942:0001:039'),
        '10:09:01:01:02:5942',
      );
      expect(cadastreBaseNumber(' 10:10:03:03:02:5799 '), '10:10:03:03:02:5799');
    });
  });

  group('findByNumber', () {
    test('raqam bo\'yicha uchastkani topadi va markazini beradi', () async {
      final client = NgisParcelClient(
        client: _client([
          (
            service: '/TURAR_UZKAD',
            where: "cadastral_number = '10:10:03:03:01:5414'",
            body: _feature('cadastral_number', '10:10:03:03:01:5414'),
          ),
        ]),
      );

      final parcel = await client.findByNumber('10:10:03:03:01:5414');

      expect(parcel, isNotNull);
      expect(parcel!.cadastreNumber, '10:10:03:03:01:5414');
      expect(parcel.layerId, 'turar');
      // Markaz — joylashuv qadamini oqimdan olib tashlaydigan nuqta.
      expect(parcel.center, isNotNull);
      expect(parcel.center!.latitude, closeTo(41.31, 0.01));
      expect(parcel.center!.longitude, closeTo(69.24, 0.01));
    });

    test('`/01` topilmasa DUMSIZ asos bilan qayta so\'raladi', () async {
      // Jonli tekshirilgan: geoportalda `.../5414/01` yo'q, `...:5414` bor.
      final log = <String>[];
      final client = NgisParcelClient(
        client: _client(
          [
            (
              service: '/TURAR_UZKAD',
              where: "cadastral_number = '10:10:03:03:01:5414'",
              body: _feature('cadastral_number', '10:10:03:03:01:5414'),
            ),
          ],
          log: log,
        ),
      );

      final parcel = await client.findByNumber('10:10:03:03:01:5414/01');

      expect(parcel?.cadastreNumber, '10:10:03:03:01:5414');
      // Avval raqamning o'zi so'raladi — qatlamda aynan shunday yozuv bo'lsa,
      // asosga tushish shart emas.
      expect(
        log.any((e) => e.contains("= '10:10:03:03:01:5414/01'")),
        isTrue,
        reason: 'to\'liq raqam umuman so\'ralmagan',
      );
    });

    test('xatlovsiz qatlamdagi uy ham topiladi (boshqa maydon nomi)', () async {
      // Qo'lda kiritilgan 10:10:03:03:02:5799 aynan shu qatlamda turadi.
      final client = NgisParcelClient(
        client: _client([
          (
            service: '/DKYAT_2023',
            where: "kadastr = '10:10:03:03:02:5799'",
            body: _feature('kadastr', '10:10:03:03:02:5799'),
          ),
        ]),
      );

      final parcel = await client.findByNumber('10:10:03:03:02:5799');

      expect(parcel?.layerId, 'xatlovsiz');
    });

    test('ikki qatlamda bo\'lsa — ANIQROG\'I (turar) tanlanadi', () async {
      final client = NgisParcelClient(
        client: _client([
          (
            service: '/TURAR_UZKAD',
            where: "cadastral_number = '10:10:03:03:01:5414'",
            body: _feature('cadastral_number', '10:10:03:03:01:5414'),
          ),
          (
            service: '/DKYAT_2023',
            where: "kadastr = '10:10:03:03:01:5414'",
            body: _feature('kadastr', '10:10:03:03:01:5414'),
          ),
        ]),
      );

      expect(
        (await client.findByNumber('10:10:03:03:01:5414'))?.layerId,
        'turar',
      );
    });

    test('topilmasa `null` — bu XATO emas', () async {
      final client = NgisParcelClient(client: _client(const []));
      expect(await client.findByNumber('10:10:03:03:02:5799'), isNull);
    });

    test('qatlam yiqilsa qolganlari ishlayveradi', () async {
      final failing = MockClient((req) async {
        final where = Uri.splitQueryString(req.body)['where'] ?? '';
        if (req.url.path.contains('/TURAR_UZKAD')) {
          return http.Response('boom', 500);
        }
        if (req.url.path.contains('/DKYAT_2023') &&
            where == "kadastr = '10:10:03:03:02:5799'") {
          return http.Response(
            _feature('kadastr', '10:10:03:03:02:5799'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(_empty, 200);
      });

      final client = NgisParcelClient(client: failing);
      expect(
        (await client.findByNumber('10:10:03:03:02:5799'))?.layerId,
        'xatlovsiz',
      );
    });
  });
}
