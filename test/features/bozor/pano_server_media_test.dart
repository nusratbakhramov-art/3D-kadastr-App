import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/data/bozor_submit.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/tour_link.dart';

/// 360° panorama SERVERDA tikiladi — e'lon uni QAYTA YUKLAMASLIGI kerak.
///
/// Foto va planirovkadan farqli, panorama sehrgar ichida allaqachon
/// `listings/media/{user_id}/` ga tushgan (`panorama` Celery navbati).
/// `DescriptionDraft.panoramas` shu sababli LOKAL YO'L emas, S3 KALITI
/// saqlaydi, va u bilan birga `uploadedMedia` ga `kalit → kalit` yozuvi
/// qo'yiladi.
///
/// Agar shu shartnoma buzilsa, `bozor_submit` kalitni fayl yo'li deb bilib
/// `MultipartFile.fromPath` ga beradi va yuborish `FileSystemException`
/// bilan yiqiladi — foydalanuvchi yetti qadam to'ldirib, oxirida.
void main() {
  const key = 'listings/media/3/pano_7_1789.jpg';

  BozorDraft draftWithServerPano({List<TourLink> tour = const []}) {
    final d = BozorDraft(
      deal: DealType.rent,
      kind: PropertyKind.residential,
      type: PropertyType.apartment,
    );
    d.title = 'Test';
    d.address.address = 'Chilonzor 5';
    d.price.amount = '1000';
    d.contacts
      ..name = 'Ali'
      ..phones.clear();
    d.contacts.phones.add('901234567');
    // `pano_capture_flow` aynan shu uchtasini yozadi.
    d.description.panoramas.add(key);
    d.description.panoramaUrls[key] = 'https://cdn.test/$key';
    d.description.uploadedMedia[key] = key;
    d.description.tourLinks.addAll(tour);
    return d;
  }

  /// `POST /listings/media` chaqirilsa — shartnoma buzilgan.
  ({http.Client client, List<String> uploads, List<Map<String, dynamic>> created})
      recorder() {
    final uploads = <String>[];
    final created = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/listings/media')) {
        uploads.add(req.url.path);
        return http.Response('{"role":"panorama","files":[]}', 201);
      }
      if (req.url.path.endsWith('/listings/')) {
        created.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{"id": 11, "status": "pending"}', 201,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    return (client: client, uploads: uploads, created: created);
  }

  test('serverda tayyor panorama QAYTA YUKLANMAYDI', () async {
    final r = recorder();
    final submitter = BozorSubmitter(api: BozorApi(client: r.client));

    await submitter.submit(draftWithServerPano());

    expect(
      r.uploads,
      isEmpty,
      reason: 'panorama allaqachon serverda — `/listings/media` chaqirilmasin',
    );
  });

  test('panorama media roʻyxatiga `role: panorama` bilan tushadi', () async {
    final r = recorder();
    await BozorSubmitter(api: BozorApi(client: r.client))
        .submit(draftWithServerPano());

    expect(r.created, hasLength(1));
    final media = ((r.created.single['description'] as Map)['media'] as List)
        .cast<Map<String, dynamic>>();
    expect(media, hasLength(1));
    expect(media.single['key'], key);
    expect(media.single['role'], 'panorama');
    // Muqova FAQAT foto bo'ladi — panorama lenta kartasida ko'rinmasin.
    expect(media.single['is_cover'], isFalse);
  });

  test('tur havolasi kalit boʻyicha ishlaydi (oʻgirish kerak emas)', () {
    // ⚠️ MUHIM: `resolveTourLinks` ilgari LOKAL YO'Lni kalitga o'girardi
    // (`uploaded[ref]`). Endi `panoramas` o'zi kalit saqlaydi, ya'ni
    // o'girish AYNIYAT bo'ladi (`uploaded[ref] ?? ref`). Shu ishlashi
    // shart, aks holda tur havolalari jimgina TASHLANADI.
    const key2 = 'listings/media/3/pano_8_1790.jpg';
    final d = draftWithServerPano(tour: [
      const TourLink(from: key, to: key2, yawDeg: 90, pitchDeg: 0),
    ]);
    d.description.panoramas.add(key2);
    d.description.uploadedMedia[key2] = key2;

    final resolved = resolveTourLinks(
      d.description.tourLinks,
      uploaded: d.description.uploadedMedia,
      allowedKeys: {key, key2},
    );

    expect(resolved, hasLength(1));
    expect(resolved.single['from_key'], key);
    expect(resolved.single['to_key'], key2);
  });

  test('qoralama saqlanib tiklanganda kalit va URL yoʻqolmaydi', () {
    final d = draftWithServerPano();
    final back = draftFromPayload(draftToDraftPayload(d));

    expect(back.description.panoramas, [key]);
    expect(back.description.panoramaUrls[key], 'https://cdn.test/$key');
    expect(
      back.description.uploadedMedia[key],
      key,
      reason: 'busiz davom ettirilgan qoralama panoramani QAYTA yuklashga '
          'urinadi va yiqiladi',
    );
  });
}
