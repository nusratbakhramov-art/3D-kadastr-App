/// Tugatilmagan qoralamani sehrgarga qaytarish.
///
/// Naqsh `lib/features/services/ai_draft_resume.dart` dan olingan: qaysi
/// ekrandan davom etish mantig'i BITTA joyda turadi, shunda "Mening
/// e'lonlarim" ro'yxati va kelajakdagi boshqa kirish nuqtalari bir xil
/// ishlaydi.
library;

import 'package:flutter/material.dart';

import 'bozor_routes.dart';
import 'bozor_step_route.dart';
import 'data/bozor_draft_codec.dart';
import 'models/bozor_draft.dart';
import 'models/bozor_listing.dart';

/// Saqlangan qadamdan mos ekranni quradi.
///
/// [step] noma'lum bo'lsa 1-qadam ochiladi ([wizardStepFromName] shunday
/// qaraydi) — bo'sh ekran ko'rsatgandan yaxshi.
///
/// ⚠️ Qoralama tanlangan mulk TURIGA bog'liq qadamlar ro'yxatiga ega
/// (`BozorDraft.wizardSteps`). Saqlangan qadam shu ro'yxatda BO'LMASA
/// (masalan qoralama "Kvartira" da `params` qadamida saqlangan, keyin tur
/// "Boshqa noturar joy" ga o'zgargan) foydalanuvchi mavjud bo'lmagan
/// ekranga tushib qolardi — shuning uchun bunday holatda ro'yxatdagi eng
/// yaqin oldingi qadamga tushiriladi.
Widget bozorStepScreenSafe(BozorDraft draft, WizardStep step) {
  final steps = draft.wizardSteps;
  final safe = steps.contains(step) ? step : _fallbackStep(steps, step);
  return bozorStepScreen(draft, safe);
}

/// `WizardStep.values` tartibida [step] dan oldinda turgan va [steps] ichida
/// mavjud bo'lgan eng oxirgi qadam. Topilmasa 1-qadam.
WizardStep _fallbackStep(List<WizardStep> steps, WizardStep step) {
  for (var i = WizardStep.values.indexOf(step) - 1; i >= 0; i--) {
    final candidate = WizardStep.values[i];
    if (steps.contains(candidate)) return candidate;
  }
  return WizardStep.type;
}

/// Marshrut nomi — qadam nomi bilan bir xil (`bozor/price`), shu sababli
/// [closeBozorWizard] qoralamadan ochilgan oqimni ham bittada yopadi.
Route<void> bozorResumeRoute(BozorDraft draft, WizardStep step) =>
    MaterialPageRoute<void>(
      settings: bozorRoute(step.name),
      builder: (_) => bozorStepScreenSafe(draft, step),
    );

/// Qoralama kartasi bosilganda: payload'dan qoralamani tiklab, saqlangan
/// qadamni ochadi.
///
/// `draftId` tiklangan qoralamaga YOZILADI — keyingi qadam saqlashlari
/// YANGI qatorni yaratmasin, o'sha qoralamani yangilasin.
///
/// ⚠️ OLDINGI QADAMLAR HAM STACK'GA QO'YILADI (animatsiyasiz). Ilgari faqat
/// saqlangan qadam push qilinardi va u yerdagi «Ortga» (`maybePop`)
/// foydalanuvchini oldingi qadamga emas, RO'YXATGA qaytarib yuborardi
/// (prod, 2026-09-13). Endi 6-qadamdan «Ortga» → 5-qadam, header'dagi ←
/// esa avvalgidek [closeBozorWizard] bilan butun oqimni yopadi — hamma
/// marshrut `bozor/<qadam>` nomli.
Future<void> openBozorDraft(BuildContext context, BozorDraftSummary summary) {
  final draft = draftFromPayload(summary.payload, draftId: summary.id);
  final step = wizardStepFromName(summary.currentStep);
  return pushBozorDraftStack(Navigator.of(context), draft, step);
}

/// [step] gacha bo'lgan qadamlarni (o'zi ham) navigatorga qo'yadi; faqat
/// oxirgisi animatsiya bilan. Sof navigatsiya — test uchun alohida.
Future<void> pushBozorDraftStack(
  NavigatorState nav,
  BozorDraft draft,
  WizardStep step,
) {
  final steps = draft.wizardSteps;
  final safe = steps.contains(step) ? step : _fallbackStep(steps, step);
  for (final prev in steps.takeWhile((s) => s != safe)) {
    nav.push(
      PageRouteBuilder<void>(
        settings: bozorRoute(prev.name),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => bozorStepScreen(draft, prev),
      ),
    );
  }
  return nav.push(bozorResumeRoute(draft, safe));
}
