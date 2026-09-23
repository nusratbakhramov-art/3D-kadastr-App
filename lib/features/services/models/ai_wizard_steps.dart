/// AI Baholash sehrgarining qadamlari.
///
/// ⚠️ NEGA MODEL KERAK BO'LDI. Ilgari har ekran progress chizig'ini QO'LDA
/// yozardi — `StepProgressBar(count: 7, activeIndex: 2)`. Qadamlar soni
/// o'zgarmas bo'lguncha bu ishlayotgandek tuyulardi. «Joylashuv» qadami
/// shartli bo'lgach (uchastka yoki reyestr ishonchli nuqta bergan bo'lsa u
/// KERAK EMAS) qat'iy raqamlar buziladi: chiziq 7 ta bo'lakni ko'rsatadi,
/// foydalanuvchi esa 6 tasidan o'tadi va oxirgi qadamda chiziq to'lmay
/// qoladi. Endi raqam bitta joydan — [AiBaholashBundle.aiSteps] dan keladi.
///
/// Naqsh yangi emas: "Bozor AI" sehrgarida aynan shunday
/// (`bozor_draft.dart` → `wizardStepsFor`, `stepNumber`, `stepIndex`).
library;

import 'ai_baholash_bundle.dart';

/// Sehrgar ekranlari, ko'rinish tartibida.
enum AiStep {
  /// Kadastr raqami: xaritadan uchastka tanlash yoki qo'lda kiritish.
  cadastre,

  /// Buyurtmachi ma'lumotlari.
  client,

  /// Obyekt joylashuvi xaritada — SHARTLI, [aiStepsFor] ga qarang.
  location,

  /// Baholash maqsadi.
  purpose,

  /// Hujjat va rasmlar.
  intake,

  /// Tekshirib chiqish.
  review,

  /// Smeta qiymati.
  targetPrice,
}

/// Shu arizada ko'rinadigan qadamlar.
///
/// «Joylashuv» faqat obyektning ishonchli nuqtasi HALI YO'Q bo'lganda
/// qo'shiladi. Uchastka geoportalda tanlangan bo'lsa (yoki reyestr koordinata
/// bergan bo'lsa) foydalanuvchidan bir xil obyektni ikkinchi marta belgilash
/// SO'RALMAYDI — mijozning asosiy shikoyati aynan shu edi.
List<AiStep> aiStepsFor({required bool needsManualLocation}) => [
  AiStep.cadastre,
  AiStep.client,
  if (needsManualLocation) AiStep.location,
  AiStep.purpose,
  AiStep.intake,
  AiStep.review,
  AiStep.targetPrice,
];

extension AiWizardStepsX on AiBaholashBundle {
  /// Shu ariza uchun ko'rinadigan qadamlar ro'yxati.
  List<AiStep> get aiSteps =>
      aiStepsFor(needsManualLocation: needsManualLocation);

  /// Progress chizig'idagi bo'laklar soni.
  int get aiStepCount => aiSteps.length;

  /// `StepProgressBar.activeIndex` uchun 0 dan boshlanadigan indeks.
  ///
  /// Qadam ro'yxatda bo'lmasa (masalan «Joylashuv» ekrani ochiq turganda
  /// foydalanuvchi uchastkani tanlab, u shartli ravishda ro'yxatdan chiqib
  /// ketsa) `-1` emas, eng yaqin mavjud qadamning indeksi qaytadi — chiziq
  /// sakrab ketmasin.
  int aiStepIndex(AiStep step) {
    final steps = aiSteps;
    final i = steps.indexOf(step);
    if (i >= 0) return i;
    for (var j = AiStep.values.indexOf(step) - 1; j >= 0; j--) {
      final k = steps.indexOf(AiStep.values[j]);
      if (k >= 0) return k;
    }
    return 0;
  }
}
