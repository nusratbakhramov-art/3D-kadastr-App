import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/data/bozor_submit.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';

/// Yuborish oqimi — fayllar bittalab, qisman muvaffaqiyat saqlanadi.
///
/// Nega bu MUHIM: `AuthHttpClient._toReplayable` multipart'ni to'liq baytga
/// o'qiydi (`finalize().toBytes()`) va `_cloneRequest` yana nusxa oladi.
/// Fayllar bitta so'rovda ketsa 20 × 20 MB ≈ 800 MB — telefonda OOM.
/// Shu sababli har bir so'rovda AYNAN BITTA fayl bo'lishi test bilan
/// qotirilgan: bu ko'rinmaydigan, lekin qurilmada ilovani o'ldiradigan xato.

late Directory _tmp;

/// Haqiqiy fayl kerak: `MultipartFile.fromPath` diskdan o'qiydi.
List<String> _files(int n) => [
  for (var i = 0; i < n; i++)
    (File('${_tmp.path}/f$i.jpg')..writeAsBytesSync([1, 2, 3])).path,
];

BozorDraft _draft({List<String> photos = const []}) {
  final d = BozorDraft(
    deal: DealType.rent,
    kind: PropertyKind.residential,
    type: PropertyType.apartment,
  );
  d.title = 'Test';
  d.address.address = 'Chilonzor 5';
  d.price.amount = '1000';
  d.contacts.name = 'Ali';
  d.contacts.phones
    ..clear()
    ..add('901234567');
  d.description.photos.addAll(photos);
  return d;
}

/// Har bir `POST /listings/media` so'rovidagi fayl sonini yozib boradi.
class _Recorder {
  final List<int> filesPerRequest = [];
  final List<String> roles = [];
  int listingPosts = 0;

  /// [failFrom] — shu indeksdan boshlab yuklash 500 qaytaradi.
  BozorApi api({int? failFrom}) {
    var n = 0;
    return BozorApi(
      client: MockClient((req) async {
        if (req.url.path.endsWith('/listings/media')) {
          // `latin1`: multipart tanasi IKKILIK, UTF-8 dekodlash unda yiqiladi.
          // `MockClient` FINALIZE qilingan `Request` beradi, ya'ni `bodyBytes`
          // har doim mavjud.
          final raw = latin1.decode(req.bodyBytes, allowInvalid: true);
          filesPerRequest.add(RegExp('filename=').allMatches(raw).length);
          roles.add(
            RegExp('name="role"').hasMatch(raw)
                ? (RegExp(r'name="role"[\s\S]{0,8}?\r\n\r\n([a-z]+)')
                          .firstMatch(raw)
                          ?.group(1) ??
                      '?')
                : '?',
          );
          if (failFrom != null && n >= failFrom) {
            n++;
            return http.Response('{"detail":"xato"}', 500);
          }
          final key = 'listings/media/3/f${n++}.jpg';
          return http.Response.bytes(
            utf8.encode('{"files":[{"key":"$key","url":"http://x/$key"}]}'),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('/listings/')) {
          listingPosts++;
          return http.Response.bytes(
            utf8.encode('{"id": 9, "status": "pending"}'),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      }),
    );
  }
}

void main() {
  setUpAll(() => _tmp = Directory.systemTemp.createTempSync('bozor_submit'));
  tearDownAll(() => _tmp.deleteSync(recursive: true));

  test('har bir so‘rovda AYNAN BITTA fayl (xotira uchun)', () async {
    final r = _Recorder();
    final draft = _draft(photos: _files(5));
    await BozorSubmitter(api: r.api()).submit(draft);

    expect(r.filesPerRequest.length, 5, reason: '5 fayl = 5 so‘rov');
    expect(
      r.filesPerRequest.every((c) => c == 1),
      isTrue,
      reason: 'bitta so‘rovda bittadan ko‘p fayl bo‘lsa telefonda OOM',
    );
    expect(r.listingPosts, 1);
  });

  test('progress har fayldan keyin xabar beradi', () async {
    final r = _Recorder();
    final seen = <String>[];
    await BozorSubmitter(api: r.api()).submit(
      _draft(photos: _files(3)),
      onProgress: (done, total) => seen.add('$done/$total'),
    );
    // 3 fayl + e'lonning o'zi = 4; boshlanishda 0/4.
    expect(seen.first, '0/4');
    expect(seen.last, '4/4');
    expect(seen, ['0/4', '1/4', '2/4', '3/4', '4/4']);
  });

  test('muvaffaqiyatli kalitlar qoralamaga YOZILADI', () async {
    final r = _Recorder();
    final draft = _draft(photos: _files(2));
    await BozorSubmitter(api: r.api()).submit(draft);
    expect(draft.description.uploadedMedia.length, 2);
    expect(
      draft.description.uploadedMedia.values,
      everyElement(startsWith('listings/media/')),
    );
  });

  group('qisman muvaffaqiyat', () {
    test('uzilishda yuklanganlar SAQLANADI', () async {
      final r = _Recorder();
      final draft = _draft(photos: _files(4));
      // 3-fayldan boshlab tarmoq yiqiladi.
      await expectLater(
        BozorSubmitter(api: r.api(failFrom: 2)).submit(draft),
        throwsA(isA<BozorApiException>()),
      );
      // Ikkitasi o'tdi — ular qoralamada qoldi.
      expect(draft.description.uploadedMedia.length, 2);
      expect(r.listingPosts, 0, reason: 'e‘lon yaratilmasligi kerak');
    });

    test('qayta urinish faqat QOLGANINI yuklaydi', () async {
      final draft = _draft(photos: _files(4));

      final first = _Recorder();
      await expectLater(
        BozorSubmitter(api: first.api(failFrom: 2)).submit(draft),
        throwsA(isA<BozorApiException>()),
      );
      expect(first.filesPerRequest.length, 3, reason: '2 o‘tdi + 1 yiqildi');

      // Ikkinchi urinish — endi hammasi ishlaydi.
      final second = _Recorder();
      await BozorSubmitter(api: second.api()).submit(draft);
      expect(
        second.filesPerRequest.length,
        2,
        reason: 'faqat qolgan 2 fayl ketishi kerak, 4 emas',
      );
      expect(draft.description.uploadedMedia.length, 4);
      expect(second.listingPosts, 1);
    });

    test('qayta urinishda progress allaqachon yuklanganini hisoblaydi', () async {
      final draft = _draft(photos: _files(4));
      await expectLater(
        BozorSubmitter(api: _Recorder().api(failFrom: 2)).submit(draft),
        throwsA(isA<BozorApiException>()),
      );
      final seen = <String>[];
      await BozorSubmitter(api: _Recorder().api()).submit(
        draft,
        onProgress: (done, total) => seen.add('$done/$total'),
      );
      // Umumiy son o'zgarmaydi (4 fayl + e'lon), lekin 2 tasi darhol bajarilgan.
      expect(seen.first, '2/5');
      expect(seen.last, '5/5');
    });
  });

  test('rol har bir so‘rovda to‘g‘ri ketadi', () async {
    final r = _Recorder();
    final draft = _draft(photos: _files(1));
    draft.description.planFiles.add(_files(1).first);
    // `_files` bir xil nomlarni qayta yasaydi — plan uchun boshqa fayl kerak.
    draft.description.planFiles
      ..clear()
      ..add((File('${_tmp.path}/plan.pdf')..writeAsBytesSync([9])).path);
    await BozorSubmitter(api: r.api()).submit(draft);
    expect(r.roles, ['photo', 'plan']);
  });

  test('media tartibi QORALAMA bo‘yicha, yuklash ketma-ketligi emas', () {
    // `sort_order` qoralamadagi indeksdan olinadi; muqova — birinchi foto.
    final draft = _draft(photos: ['/a.jpg', '/b.jpg']);
    draft.description.uploadedMedia.addAll({
      '/a.jpg': 'listings/media/3/a.jpg',
      '/b.jpg': 'listings/media/3/b.jpg',
    });
    final payload = BozorSubmitter.buildPayload(draft, const [
      {'key': 'listings/media/3/a.jpg', 'role': 'photo', 'sort_order': 0,
       'is_cover': true},
      {'key': 'listings/media/3/b.jpg', 'role': 'photo', 'sort_order': 1,
       'is_cover': false},
    ]);
    final media = (payload['description'] as Map)['media'] as List;
    expect((media[0] as Map)['is_cover'], isTrue);
    expect((media[1] as Map)['sort_order'], 1);
  });
}
