import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_store.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';

/// Tahrirlash sehrgari qoralamani TAKRORLAMASLIGI.
///
/// ⚠️ Buzilganda hech qanday xato bo'lmaydi: «Tahrirlash» har bosilganda
/// «Mening e'lonlarim» ga yana bitta karta qo'shiladi va foydalanuvchi buni
/// e'lon tahrirlanmay, NUSXA ochilgani deb ko'radi. Ustiga-ustak 20 talik
/// chegaraga yetganda backend eng eski HAQIQIY qoralamani jimgina o'chiradi.
void main() {
  BozorDraft draft({int? editingId, int? draftId}) {
    final d = BozorDraft(
      deal: DealType.rent,
      kind: PropertyKind.residential,
      type: PropertyType.apartment,
    )
      ..editingListingId = editingId
      ..draftId = draftId;
    d.title = 'Chilonzor';
    return d;
  }

  /// Serverdagi qoralamalar ro'yxatini imitatsiya qiladi va ko'rilgan
  /// so'rovlarni yozib boradi.
  ///
  /// [drafts] — `(id, editingListingId)` juftliklari; `null` = oddiy
  /// (tahrir emas) qoralama.
  ({List<String> seen, BozorApi api}) recorder(
    List<(int, int?)> drafts,
  ) {
    final seen = <String>[];
    final api = BozorApi(
      client: MockClient((req) async {
        seen.add('${req.method} ${req.url.path}');
        final body = req.method == 'GET'
            ? {
                'items': [
                  for (final (id, editing) in drafts)
                    {
                      'id': id,
                      'current_step': 'address',
                      'payload': {
                        'title': 'Chilonzor',
                        kEditingListingKey: ?editing,
                      },
                      'created_at': '2026-09-12T10:00:00Z',
                      'updated_at': '2026-09-12T10:00:00Z',
                    },
                ],
                'total': drafts.length,
                'limit': 20,
              }
            : {'id': 999};
        return http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          req.method == 'POST' ? 201 : 200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (seen: seen, api: api);
  }

  test('tahrirning MAVJUD qoralamasi qayta ishlatiladi, yangisi EMAS', () async {
    final r = recorder([(3, null), (8, 77)]);
    final d = draft(editingId: 77);
    await persistBozorDraft(r.api, d, WizardStep.address);

    // Topilgan qator YANGILANADI.
    expect(r.seen, contains('PATCH /api/v1/listings/drafts/8'));
    expect(r.seen.where((s) => s.startsWith('POST')), isEmpty);
    // Keyingi qadamlar ham o'sha qatorga yozsin.
    expect(d.draftId, 8);
  });

  test('boshqa e\'lonning qoralamasi O\'G\'IRLANMAYDI', () async {
    // 77 ning qoralamasi yo'q — 12 nikini olib qo'ysak, foydalanuvchi bir
    // e'lonni tahrirlab, BOSHQASINI yozib yuborardi.
    final r = recorder([(8, 12)]);
    final d = draft(editingId: 77);
    await persistBozorDraft(r.api, d, WizardStep.address);

    expect(r.seen, contains('POST /api/v1/listings/drafts'));
    expect(r.seen.where((s) => s.startsWith('PATCH')), isEmpty);
    expect(d.draftId, 999);
  });

  test('ODDIY oqimda ro\'yxat UMUMAN so\'ralmaydi', () async {
    // Yangi e'londa qidiradigan narsa yo'q — ortiqcha so'rov sehrgarni
    // sekinlashtirardi.
    final r = recorder([(8, 77)]);
    await persistBozorDraft(r.api, draft(), WizardStep.address);

    expect(r.seen, ['POST /api/v1/listings/drafts']);
  });

  test('draftId ALLAQACHON bor bo\'lsa ro\'yxat so\'ralmaydi', () async {
    final r = recorder([(8, 77)]);
    await persistBozorDraft(
      r.api,
      draft(editingId: 77, draftId: 8),
      WizardStep.price,
    );

    expect(r.seen, ['PATCH /api/v1/listings/drafts/8']);
  });

  test('ro\'yxat YIQILSA yangi qoralama yaratiladi', () async {
    // Qoralama umuman saqlanmay qolgandan ko'ra, ortiqcha qator yaxshiroq.
    final api = BozorApi(
      client: MockClient((req) async {
        if (req.method == 'GET') return http.Response('boom', 500);
        return http.Response.bytes(
          utf8.encode('{"id":999}'),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final d = draft(editingId: 77);
    await persistBozorDraft(api, d, WizardStep.address);
    expect(d.draftId, 999);
  });
}
