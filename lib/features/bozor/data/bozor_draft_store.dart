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
    final payload = draftToDraftPayload(draft);
    final id = draft.draftId;
    if (id == null) {
      draft.draftId = await api.createDraft(
        payload: payload,
        currentStep: reached.name,
      );
    } else {
      await api.updateDraft(id, payload: payload, currentStep: reached.name);
    }
  } catch (_) {
    // Jim — keyingi qadamda yana urinib ko'riladi.
  } finally {
    api.dispose();
  }
}

/// Qoralamani o'chiradi (foydalanuvchi ro'yxatdan o'chirsa).
///
/// Bu esa JIM EMAS: foydalanuvchi ataylab bosgan, natijani ko'rishi kerak.
Future<void> deleteBozorDraft(int id) async {
  final api = BozorApi();
  try {
    await api.deleteDraft(id);
  } finally {
    api.dispose();
  }
}
