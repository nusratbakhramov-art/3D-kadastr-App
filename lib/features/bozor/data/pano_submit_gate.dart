/// 360° panorama sababli e'lonni yuborishga TO'SIQ bormi.
///
/// NEGA ALOHIDA VA SOF FUNKSIYA. Uchta shart bir-biriga bog'liq va
/// ularning har biri e'lonni JIMGINA buzadi:
///
///  1. **Hali tikilayotgan panorama.** `bozor_submit` kaliti yo'q yozuvni
///     `if (key == null) continue;` bilan o'tkazib yuboradi — ya'ni e'lon
///     xatosiz ketadi, panorama esa unda BO'LMAYDI. Foydalanuvchi 30
///     nishonni aylanib chiqqan mehnati jimgina yo'qoladi.
///  2. **Yiqilgan panorama.** Xuddi shunday tashlanadi.
///  3. **Turda yetib bo'lmaydigan panorama.** E'londa bor, turda yo'q:
///     ko'ruvchi unga hech qachon yetolmaydi.
///
/// Uchinchi shart ATAYLAB `unreachablePanoramas` bilan tekshiriladi,
/// «har birida kamida bitta havola bor» bilan emas. Farqi:
///
///     A ↔ B      C ↔ D
///
/// Bu yerda har bir panoramada havola BOR, lekin A dan boshlagan ko'ruvchi
/// C va D ga yetolmaydi. Zaif shart buni o'tkazib yuborardi.
library;

import '../models/bozor_draft.dart';
import '../models/tour_link.dart';

/// Yuborishga to'siq bo'lsa — foydalanuvchiga ko'rsatiladigan i18n KALITI.
/// To'siq yo'q bo'lsa `null`.
String? panoSubmitBlocker(DescriptionDraft d) {
  if (d.failedPanoramas.isNotEmpty) return 'bozor.pano.gate.failed';
  if (d.workingPanoramas.isNotEmpty) return 'bozor.pano.gate.pending';
  // Bitta panoramada tur tushunchasi yo'q — qo'shish tugmasi baribir
  // ko'rinadi, lekin talab qilinmaydi.
  if (d.panoramas.length >= 2 &&
      unreachablePanoramas(d.panoramas, d.tourLinks).isNotEmpty) {
    return 'bozor.pano.gate.tour';
  }
  return null;
}
