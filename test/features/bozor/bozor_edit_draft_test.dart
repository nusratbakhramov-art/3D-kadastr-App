import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';

/// Tahrirlash qoralamasi — MAVJUD e'londan ochilgan sehrgar.
///
/// ⚠️ BU YERDAGI HAMMA XATO JIM. Tahrirlash rejimi yoki eski fayllar
/// qoralamadan tiklanmasa hech qanday istisno bo'lmaydi: yuborish
/// shunchaki `POST` ga ketadi va foydalanuvchi asl e'lon o'zgarmaganini,
/// o'rniga nusxa paydo bo'lganini KEYIN ko'radi.
void main() {
  BozorDraft editingDraft() {
    final d = BozorDraft(
      deal: DealType.rent,
      kind: PropertyKind.residential,
      type: PropertyType.apartment,
    )..editingListingId = 77;
    d.title = 'Tahrirlanayotgan e‘lon';
    d.description.existingMedia.addAll(const <ExistingMedia>[
      ExistingMedia(key: 'listings/media/9/aaa.jpg', role: 'photo',
          sortOrder: 0, isCover: true),
      ExistingMedia(key: 'listings/media/9/bbb.jpg', role: 'panorama',
          sortOrder: 1, isCover: false),
    ]);
    return d;
  }

  group('tahrirlash qoralamasi — AYLANMA YO‘L', () {
    test('editingListingId SAQLANADI va TIKLANADI', () {
      // Busiz yuborish `POST /drafts/{id}/submit` ga ketadi va asl e'lon
      // o'rniga NUSXA yaratiladi.
      final payload = draftToDraftPayload(editingDraft());
      expect(payload[kEditingListingKey], 77);

      final back = draftFromPayload(payload, draftId: 5);
      expect(back.editingListingId, 77);
      expect(back.isEditing, isTrue);
      expect(back.draftId, 5);
    });

    test('MAVJUD fayllar saqlanadi va tiklanadi', () {
      // `PATCH` media ro'yxatini TO'LIQ almashtiradi — eski kalitlar
      // qaytarilmasa e'lonning bor rasmlari o'chib ketadi.
      final payload = draftToDraftPayload(editingDraft());
      final back = draftFromPayload(payload, draftId: 5);

      expect(back.description.existingMedia, hasLength(2));
      final first = back.description.existingMedia.first;
      expect(first.key, 'listings/media/9/aaa.jpg');
      expect(first.role, 'photo');
      expect(first.isCover, isTrue);

      final second = back.description.existingMedia[1];
      expect(second.role, 'panorama');
      expect(second.sortOrder, 1);
      expect(second.isCover, isFalse);
    });

    test('ODDIY qoralamada bu kalitlar UMUMAN yo‘q', () {
      // Yangi e'lon qoralamasiga tahrirlash kaliti tushib qolsa, yuborish
      // mavjud bo'lmagan e'lonni `PATCH` qilishga urinardi (404).
      final d = BozorDraft(
        deal: DealType.rent,
        kind: PropertyKind.residential,
        type: PropertyType.apartment,
      );
      final payload = draftToDraftPayload(d);
      expect(payload.containsKey(kEditingListingKey), isFalse);
      expect(payload.containsKey(kExistingMediaKey), isFalse);

      expect(draftFromPayload(payload).editingListingId, isNull);
      expect(draftFromPayload(payload).isEditing, isFalse);
    });

    test('kalitsiz fayl TASHLAB YUBORILADI', () {
      // Bo'sh kalit `PATCH` da 400 berardi.
      final payload = draftToDraftPayload(editingDraft())
        ..[kExistingMediaKey] = [
          {'key': '', 'role': 'photo', 'sort_order': 0, 'is_cover': false},
          {'role': 'photo'},
          {'key': 'listings/media/9/ok.jpg', 'role': 'photo',
           'sort_order': 3, 'is_cover': false},
        ];
      final back = draftFromPayload(payload);
      expect(back.description.existingMedia, hasLength(1));
      expect(back.description.existingMedia.single.key,
          'listings/media/9/ok.jpg');
    });
  });
}
