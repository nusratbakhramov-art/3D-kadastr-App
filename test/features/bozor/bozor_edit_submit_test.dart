import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/data/bozor_submit.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'param_schema_fixture.dart';

/// Mavjud e'lonni tahrirlashni YAKUNLASH.
///
/// ⚠️ Qo'riqlanadigan narsa: tahrir `PATCH /listings/{id}` ga ketishi va
/// undan keyin sehrgar yo'l-yo'lakay yaratgan QORALAMA o'chishi. Qoralama
/// qolib ketsa u «Mening e'lonlarim» da alohida yozuv bo'lib turadi va
/// undan davom ettirish asl e'lonni yana tahrirlashga olib borardi —
/// foydalanuvchi esa buni e'lon ikkilanib qolgan deb ko'radi.
void main() {
  // Sxema backenddan keladi — testda uni qo'lda yuklaymiz.
  setUpAll(loadRealParamSchema);

  BozorDraft draft({int? editingId, int? draftId}) {
    final d = BozorDraft(
      deal: DealType.rent,
      kind: PropertyKind.residential,
      type: PropertyType.apartment,
    )
      ..editingListingId = editingId
      ..draftId = draftId;
    d.title = 'Test';
    d.address.address = 'Chilonzor 5';
    d.price.amount = '1000';
    d.contacts.name = 'Ali';
    d.contacts.phones
      ..clear()
      ..add('901234567');
    return d;
  }

  /// Ko'rilgan so'rovlarni yozib boradi.
  ({List<String> seen, BozorApi api}) recorder() {
    final seen = <String>[];
    final api = BozorApi(
      client: MockClient((req) async {
        seen.add('${req.method} ${req.url.path}');
        return http.Response.bytes(
          utf8.encode('{"id":77,"status":"pending"}'),
          req.method == 'POST' ? 201 : 200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (seen: seen, api: api);
  }

  test('tahrir PATCH ga ketadi, POST ga EMAS', () async {
    final r = recorder();
    await BozorSubmitter(api: r.api).submit(draft(editingId: 77, draftId: 5));

    expect(
      r.seen.where((s) => s.startsWith('PATCH')).toList(),
      contains(matches(RegExp(r'PATCH .*/listings/77$'))),
    );
    expect(
      r.seen.any((s) => s.contains('drafts/5/submit')),
      isFalse,
      reason: 'tahrir yangi e‘lon yaratmasligi kerak',
    );
  });

  test('tahrirdan keyin QORALAMA o‘chadi', () async {
    final r = recorder();
    final d = draft(editingId: 77, draftId: 5);
    await BozorSubmitter(api: r.api).submit(d);

    expect(
      r.seen.any((s) => s.startsWith('DELETE') && s.endsWith('/drafts/5')),
      isTrue,
      reason: 'qoralama o‘chirilmadi — «Mening e‘lonlarim» da qolib ketadi',
    );
    // Mahalliy nusxada ham qolmasin: aks holda «Yana bitta qo'shish»
    // o'chirilgan qoralamani yangilashga urinardi.
    expect(d.draftId, isNull);
  });

  test('qoralamasiz tahrir ham ishlaydi', () async {
    // Tizimga kirmagan yoki tarmoq yo'q bo'lgan sessiyada qoralama
    // umuman yaratilmagan bo'ladi.
    final r = recorder();
    await BozorSubmitter(api: r.api).submit(draft(editingId: 77));
    expect(r.seen.any((s) => s.startsWith('DELETE')), isFalse);
  });

  test('qoralamani O‘CHIRIB bo‘lmasa ham tahrir SAQLANADI', () async {
    // O'chirish yiqilgani uchun foydalanuvchiga xato ko'rsatish noto'g'ri:
    // uning tahriri allaqachon serverda.
    final seen = <String>[];
    final api = BozorApi(
      client: MockClient((req) async {
        seen.add(req.method);
        if (req.method == 'DELETE') return http.Response('nope', 500);
        return http.Response.bytes(
          utf8.encode('{"id":77,"status":"pending"}'),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final d = draft(editingId: 77, draftId: 5);
    await expectLater(BozorSubmitter(api: api).submit(d), completes);
    expect(seen, contains('DELETE'));
  });
}
