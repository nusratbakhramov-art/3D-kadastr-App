import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/data/bozor_draft_codec.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';

/// Muqova rasmini FOYDALANUVCHI tanlaydi.
///
/// Ilgari muqova har doim ro'yxatdagi birinchi rasm edi va uni o'zgartirib
/// bo'lmasdi — e'lon kartasida qaysi rasm chiqishini foydalanuvchi boshqara
/// olmasdi. Tanlov havola bo'yicha saqlanadi, indeks bo'yicha emas: aks
/// holda oldingi rasm o'chirilganda muqova jimgina boshqasiga surilardi.
void main() {
  DescriptionDraft withPhotos(List<String> paths) =>
      DescriptionDraft()..photos.addAll(paths);

  group('sukut', () {
    test('tanlanmagan bo\'lsa — birinchi rasm', () {
      final d = withPhotos(['a', 'b', 'c']);
      expect(d.coverPhoto, isNull);
      expect(d.coverPhotoIndex, 0);
    });

    test('rasm umuman bo\'lmasa ham yiqilmaydi', () {
      expect(DescriptionDraft().coverPhotoIndex, 0);
    });
  });

  group('tanlash', () {
    test('tanlangan rasmning o\'rni qaytariladi', () {
      final d = withPhotos(['a', 'b', 'c'])..coverPhoto = 'c';
      expect(d.coverPhotoIndex, 2);
    });

    test('BOSHQA rasm o\'chsa muqova SURILMAYDI', () {
      final d = withPhotos(['a', 'b', 'c'])..coverPhoto = 'c';
      d.photos.remove('a');
      // Indeks 2 dan 1 ga tushdi, lekin RASM o'sha-o'sha.
      expect(d.photos[d.coverPhotoIndex], 'c');
    });

    test('muqovaning O\'ZI o\'chsa — birinchisiga qaytadi', () {
      final d = withPhotos(['a', 'b', 'c'])..coverPhoto = 'c';
      d.photos.remove('c');
      expect(d.coverPhotoIndex, 0);
      expect(d.photos[d.coverPhotoIndex], 'a');
    });
  });

  group('qoralama', () {
    BozorDraft draftWith(DescriptionDraft d) {
      final draft = BozorDraft()
        ..deal = DealType.rent
        ..type = PropertyType.apartment;
      draft.description.photos.addAll(d.photos);
      draft.description.coverPhoto = d.coverPhoto;
      return draft;
    }

    test('tanlov saqlanadi va tiklanadi', () {
      final draft = draftWith(withPhotos(['a', 'b'])..coverPhoto = 'b');
      final back = draftFromPayload(draftToDraftPayload(draft));
      expect(back.description.coverPhoto, 'b');
      expect(back.description.coverPhotoIndex, 1);
    });

    test('ro\'yxatda qolmagan havola tiklanmaydi', () {
      final draft = draftWith(withPhotos(['a', 'b']));
      // Qoralamaga o'lik havola yozamiz (eski versiyadan qolgan holat).
      final payload = draftToDraftPayload(draft);
      (payload[kLocalMediaKey] as Map)['cover_photo'] = 'zzz';
      final back = draftFromPayload(payload);
      expect(back.description.coverPhoto, isNull);
      expect(back.description.coverPhotoIndex, 0);
    });

    test('tanlanmagan qoralamada maydon umuman yozilmaydi', () {
      final draft = draftWith(withPhotos(['a']));
      final local = draftToDraftPayload(draft)[kLocalMediaKey] as Map;
      expect(local.containsKey('cover_photo'), isFalse);
    });
  });
}
