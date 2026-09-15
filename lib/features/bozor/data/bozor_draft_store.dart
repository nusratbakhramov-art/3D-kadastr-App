/// Sehrgar qoralamasini serverda saqlash.
///
/// Naqsh `lib/features/services/ai_draft_saver.dart` dan olingan: saqlash
/// JIM ishlaydi va navigatsiyani HECH QACHON bloklamaydi. Sekin yoki
/// ishlamayotgan backend sehrgarni muzlatib qo'ymasligi kerak — foydalanuvchi
/// e'lon berayotganda "saqlanmoqda" deb kutib turishi mantiqsiz.
///
/// Shu sababli xatolar yutiladi. Yo'qotish narxi past: keyingi qadamda
/// yana urinib ko'riladi va `PATCH` payload'ni TO'LIQ almashtirgani uchun
/// bitta muvaffaqiyatli saqlash oldingi hamma o'tkazib yuborilganini
/// qoplaydi.
library;

import 'dart:async';

import '../../auth/auth_storage.dart';
import '../models/bozor_draft.dart';
import 'bozor_api.dart';
import 'bozor_draft_codec.dart';

/// Qadamga o'tishda qoralamani fonda saqlaydi.
///
/// [reached] — foydalanuvchi ENDI turgan qadam, ya'ni qoralamaga qaytganda
/// shu ekran ochiladi.
void saveBozorDraftInBackground(BozorDraft draft, WizardStep reached) {
  unawaited(saveBozorDraft(draft, reached));
}

/// Qoralamani saqlaydi: birinchi chaqiruvda yaratadi, keyin yangilaydi.
///
/// `draft.draftId` JOYIDA to'ldiriladi — sehrgar bo'ylab bitta nusxa
/// yurgani uchun keyingi ekranlar ham o'sha id'ni ko'radi.
///
/// Tizimga kirmagan foydalanuvchida hech narsa qilmaydi: qoralama server
/// tomonda saqlanadi, ya'ni tokensiz saqlashning iloji yo'q. Bu holatda
/// sehrgar avvalgidek ishlashda davom etadi (xotiradagi qoralama bilan) va
/// yuborish `POST /listings/` orqali ketadi.
Future<void> saveBozorDraft(BozorDraft draft, WizardStep reached) async {
  final session = await const AuthStorage().loadSession();
  final token = session.token;
  if (token == null || token.isEmpty) return;

  final api = BozorApi();
  try {
    await persistBozorDraft(api, draft, reached);
  } catch (_) {
    // Jim — keyingi qadamda yana urinib ko'riladi.
  } finally {
    api.dispose();
  }
}

/// Qoralama qatorini serverda ta'minlaydi: bori yangilanadi, yo'g'i yaratiladi.
///
/// [saveBozorDraft] dan ayri turishining sababi — SINALISHI: bu yerda na
/// `AuthStorage`, na `BozorApi()` qurilishi bor, ya'ni testda `MockClient`
/// bilan haydash mumkin. Xatolar bu yerda YUTILMAYDI — ularni chaqiruvchi
/// yutadi.
Future<void> persistBozorDraft(
  BozorApi api,
  BozorDraft draft,
  WizardStep reached,
) async {
  final payload = draftToDraftPayload(draft);
  // ⚠️ Tahrirlashda YANGI qator yaratish TAQIQLANADI. «Tahrirlash» har
  // bosilganda `draftFromListing` `draftId` siz qoralama beradi, ya'ni bu yer
  // `createDraft` ga tushardi va «Mening e'lonlarim» ga yana bitta karta
  // qo'shilardi — foydalanuvchi buni e'lon tahrirlanmay, NUSXA ochilgani deb
  // ko'radi. Tahrir oxiriga yetkazilmasa (odatiy hol) karta abadiy qolardi,
  // 20 talik chegaraga yetganda esa backend eng eski HAQIQIY qoralamani
  // jimgina o'chirardi.
  //
  // Shuning uchun bitta e'longa BITTA tahrir-qoralamasi.
  final id = draft.draftId ?? await _existingEditDraftId(api, draft);
  if (id == null) {
    draft.draftId = await api.createDraft(
      payload: payload,
      currentStep: reached.name,
    );
    return;
  }
  draft.draftId = id;
  await api.updateDraft(id, payload: payload, currentStep: reached.name);
}

/// Shu e'lon uchun ALLAQACHON ochilgan tahrir-qoralamasi (bo'lsa).
///
/// Tahrirlash EMAS (oddiy, yangi e'lon oqimi) bo'lsa so'rov UMUMAN
/// yuborilmaydi — sehrgarni ortiqcha kutdirmaslik uchun.
///
/// Xato yutiladi va `null` qaytadi: ro'yxatni ololmaslik sababli qoralama
/// saqlanmay qolgandan ko'ra, yangi qator yaratilgani yaxshiroq.
Future<int?> _existingEditDraftId(BozorApi api, BozorDraft draft) async {
  final listingId = draft.editingListingId;
  if (listingId == null) return null;
  try {
    for (final d in await api.drafts()) {
      if (editingListingIdOf(d) == listingId) return d.id;
    }
  } catch (_) {
    // Jim — chaqiruvchi `createDraft` ga tushadi.
  }
  return null;
}
