/// Qadam → ekran xaritasi va keyingi qadamga o'tish.
///
/// NEGA ALOHIDA FAYL. Bu xarita ikki tarafdan kerak: `bozor_resume.dart`
/// qoralamani SAQLANGAN qadamdan ochadi, sehrgar ekranlari esa KEYINGI
/// qadamga o'tadi. Ikkalasi `bozor_resume.dart` da tursa ekranlar uni import
/// qilib import sikli yasardi (`resume → ekran → resume`), har birida o'z
/// `switch` i bo'lsa esa yangi qadam qo'shilganda ular birin-ketin unutilardi
/// — aynan shu xato «Сделка» qadamini ijara oqimiga ham chiqarib yuborardi.
///
/// ⚠️ Oqimga yangi ekran qo'shilganda [bozorStepScreen] ga qator qo'shish
/// SHART — `WizardStep` to'liq qamralmasa analizator xato beradi, ya'ni
/// unutib bo'lmaydi.
library;

import 'package:flutter/material.dart';

import 'bozor_routes.dart';
import 'data/bozor_draft_store.dart';
import 'models/bozor_draft.dart';
import 'screens/bozor_address_step_screen.dart';
import 'screens/bozor_contacts_step_screen.dart';
import 'screens/bozor_deal_step_screen.dart';
import 'screens/bozor_description_step_screen.dart';
import 'screens/bozor_params_step_screen.dart';
import 'screens/bozor_price_step_screen.dart';
import 'screens/bozor_terms_step_screen.dart';
import 'screens/bozor_type_step_screen.dart';

/// Qadamning ekrani. Ro'yxatda bo'lmagan qadam ham chiziladi — tekshiruv
/// chaqiruvchida ([bozorStepScreenSafe] ga qarang).
Widget bozorStepScreen(BozorDraft draft, WizardStep step) => switch (step) {
  WizardStep.type => BozorTypeStepScreen(draft: draft),
  WizardStep.address => BozorAddressStepScreen(draft: draft),
  WizardStep.params => BozorParamsStepScreen(draft: draft),
  WizardStep.deal => BozorDealStepScreen(draft: draft),
  WizardStep.price => BozorPriceStepScreen(draft: draft),
  WizardStep.description => BozorDescriptionStepScreen(draft: draft),
  WizardStep.contacts => BozorContactsStepScreen(draft: draft),
  WizardStep.terms => BozorTermsStepScreen(draft: draft),
};

/// [current] dan KEYINGI qadamni ochadi.
///
/// Keyingisi qaysi ekran ekanini chaqiruvchi bilmaydi va bilmasligi ham
/// kerak: u (e'lon turi × mulk turi) juftligiga bog'liq
/// ([BozorDraft.wizardSteps]). Masalan manzildan keyin ijarada «Параметры»,
/// sotuvda esa «Другая нежилая» bo'lsa to'g'ridan «Сделка» keladi.
///
/// Qoralama fonda saqlanadi — foydalanuvchi shu qadamda chiqib ketsa
/// "Mening e'lonlarim" dan aynan shu joydan davom etadi. `await`
/// QILINMAYDI: tarmoq navigatsiyani muzlatmasin.
///
/// Oxirgi qadamda (keyingisi yo'q) hech narsa qilmaydi.
Future<void> openNextBozorStep(
  BuildContext context,
  BozorDraft draft,
  WizardStep current,
) async {
  final next = draft.stepAfter(current);
  if (next == null) return;
  saveBozorDraftInBackground(draft, next);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      // Marshrut nomi qadam nomi bilan bir xil (`bozor/deal`) — shunda
      // `closeBozorWizard` butun oqimni bittada yopadi.
      settings: bozorRoute(next.name),
      builder: (_) => bozorStepScreen(draft, next),
    ),
  );
}
