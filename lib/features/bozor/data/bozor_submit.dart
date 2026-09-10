/// Qoralamani backendga yuborish.
///
/// Ikki bosqich: avval fayllar yuklanadi (`POST /listings/media`), keyin
/// e'lonning o'zi (`POST /listings/`) — yuklash kalitlari bilan.
///
/// Nega alohida fayl: 7-qadam ekrani UI bilan band, bu yerda esa tarmoq
/// ketma-ketligi va xatolar. Ikkalasi bir joyda bo'lsa ekran o'qib
/// bo'lmaydigan bo'lib ketardi.
library;

import '../models/bozor_draft.dart';
import 'bozor_api.dart';
import 'bozor_draft_codec.dart';

/// Yuklash jarayonining holati — ekran progress ko'rsatishi uchun.
typedef SubmitProgress = void Function(int done, int total);

class BozorSubmitter {
  BozorSubmitter({BozorApi? api}) : _api = api ?? BozorApi();

  final BozorApi _api;

  /// Qoralamani yuboradi va yaratilgan e'lonni qaytaradi.
  ///
  /// Xatolikda [BozorApiException] tashlaydi — ekran uni foydalanuvchiga
  /// ko'rsatadi va qoralama JOYIDA qoladi, ya'ni qayta urinish mumkin.
  Future<Map<String, dynamic>> submit(
    BozorDraft draft, {
    SubmitProgress? onProgress,
  }) async {
    final d = draft.description;

    // ── 1. Fayllar ────────────────────────────────────────────────────────
    // Rollar bo'yicha alohida so'rov: backend `role` ni forma maydonida
    // kutadi va har rolning o'z chegarasi bor.
    final groups = <String, List<String>>{
      'photo': d.photos,
      'plan': d.planFiles,
      'panorama': d.panoramas,
    }..removeWhere((_, v) => v.isEmpty);

    final total = groups.length + 1; // + e'lonning o'zi
    var done = 0;
    void tick() => onProgress?.call(++done, total);

    final media = <Map<String, Object?>>[];
    for (final entry in groups.entries) {
      final uploaded = await _api.uploadMedia(
        role: entry.key,
        paths: entry.value,
      );
      for (var i = 0; i < uploaded.length; i++) {
        media.add({
          'key': uploaded[i].key,
          'role': entry.key,
          'sort_order': i,
          // Muqova — birinchi foto. Backend ham shu qoidaga tushadi, lekin
          // aniq aytib qo'ygan yaxshi.
          'is_cover': entry.key == 'photo' && i == 0,
        });
      }
      tick();
    }

    // ── 2. E'lon ──────────────────────────────────────────────────────────
    // Tahrirlash: yangi e'lon YARATILMAYDI, mavjudi yangilanadi.
    final editingId = draft.editingListingId;
    if (editingId != null) {
      // Mavjud fayllar KALIT bilan qaytariladi — `PATCH` media ro'yxatini
      // to'liq almashtiradi. Ular bilan birga yangi yuklanganlar ham ketadi
      // (M1-9 da tahrirlash faqat QO'SHADI; o'chirish M4-25).
      final keep = [
        for (final m in d.existingMedia)
          {
            'key': m.key,
            'role': m.role,
            'sort_order': m.sortOrder,
            'is_cover': m.isCover,
          },
      ];
      // Yangi fayl qo'shilmagan bo'lsa MEDIA UMUMAN yuborilmaydi: server
      // unga tegmaydi va muqova/tartib o'zgarmasdan qoladi.
      final all = media.isEmpty
          ? const <Map<String, Object?>>[]
          : [...keep, ...media];
      final updated = await _api.updateListing(
        editingId,
        draftToUpdatePayload(draft, all),
      );
      tick();
      return updated;
    }

    final payload = buildPayload(draft, media);
    final draftId = draft.draftId;
    if (draftId == null) {
      // Qoralama saqlanmagan (tizimga kirilmagan yoki har qadamda tarmoq
      // yo'q edi) — to'g'ridan-to'g'ri yaratamiz.
      final created = await _api.createListing(payload);
      tick();
      return created;
    }

    // Qoralama BOR — e'lon ALBATTA shu qoralamadan yaratilishi kerak.
    // `POST /listings/` bilan yuborsak qoralama serverda yetim qolib,
    // "Mening e'lonlarim" da bir e'lon IKKI marta (qoralama + e'lon bo'lib)
    // ko'rinardi.
    //
    // `submit` tana yubormaydi va payload'ni qoralamadan oladi — shuning
    // uchun avval yuklangan fayl kalitlarini qoralamaga yozib qo'yamiz.
    // Bu `PATCH` ni `await` QILAMIZ (qadam saqlashlaridan farqli): u
    // muvaffaqiyatsiz bo'lsa e'lon rasmsiz chiqib ketardi.
    await _api.updateDraft(
      draftId,
      payload: payload,
      currentStep: WizardStep.terms.name,
    );
    final created = await _api.submitDraft(draftId);
    // Server qoralamani o'chirdi — mahalliy nusxada ham id qolmasin, aks
    // holda "Yana bitta qo'shish" o'chirilgan qoralamani yangilashga
    // urinardi (404).
    draft.draftId = null;
    tick();
    return created;
  }

  /// So'rov tanasi. Ochiq — testda tekshirish uchun.
  ///
  /// Amalda `bozor_draft_codec.dart` bajaradi: qoralama saqlash ham SHU
  /// funksiyani ishlatadi, ya'ni yuborilgan e'lon va saqlangan qoralama
  /// hech qachon boshqa shaklda bo'lmaydi.
  static Map<String, dynamic> buildPayload(
    BozorDraft draft,
    List<Map<String, Object?>> media,
  ) => draftToPayload(draft, media);

  void dispose() => _api.dispose();
}

// Enum ↔ kod o'girmasi `bozor_draft_codec.dart` da — u ikki yo'nalishni
// (yozish va o'qish) yonma-yon saqlaydi, shu sababli bu yerda takrorlanmaydi.
