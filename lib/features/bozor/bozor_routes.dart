/// "Bozor AI" sehrgarining marshrut nomlari.
///
/// AI Baholash oqimidagi bilan bir xil qoida: oqimning HAR BIR ekrani
/// [bozorRoutePrefix] bilan boshlanuvchi nom bilan `push` qilinadi, shunda
/// [closeBozorWizard] yetti qadamni birma-bir bosmasdan bittada chiqib ketadi.
///
/// DIQQAT: oqimga yangi ekran qo'shilganda `RouteSettings(name: ...)` berish
/// SHART — nomsiz marshrut yopishni o'zida to'xtatib qo'yadi.
library;

import 'package:flutter/material.dart';

import '../../core/i18n/app_translations.dart';
import '../../widgets/exit_wizard_sheet.dart';

const String bozorRoutePrefix = 'bozor/';

/// Oqim ekranining marshrut sozlamasi. `bozorRoute('type')` → `bozor/type`.
RouteSettings bozorRoute(String name) =>
    RouteSettings(name: '$bozorRoutePrefix$name');

/// Butun sehrgarni yopadi — qadamma-qadam emas, bittada. Oqim qayerdan
/// ochilgan bo'lsa (bosh sahifadagi "Bozor AI" kartasi), o'sha yerga qaytadi.
void closeBozorWizard(BuildContext context) {
  Navigator.of(context).popUntil((route) {
    final name = route.settings.name;
    return name == null || !name.startsWith(bozorRoutePrefix);
  });
}

/// Oqimdan chiqishni TASDIQLATADI va tasdiqlansa butun sehrgarni yopadi.
///
/// Oynaning o'zi [confirmLeaveWizard] da — AI Baholash ham aynan shu
/// drawer'ni ko'rsatadi, faqat matnlari boshqa.
///
/// Qaytadi: foydalanuvchi chiqishni tasdiqladimi.
Future<bool> confirmCloseBozorWizard(BuildContext context) async {
  final l = Localizations.localeOf(context);
  final leave = await confirmLeaveWizard(
    context,
    title: tr(l, 'bozor.exit.title'),
    body: tr(l, 'bozor.exit.body'),
    stayLabel: tr(l, 'bozor.exit.stay'),
    leaveLabel: tr(l, 'bozor.exit.leave'),
  );
  if (!leave || !context.mounted) return false;
  closeBozorWizard(context);
  return true;
}

/// Qadam sarlavhasidagi ← amali.
///
/// ODDIY QADAM: bitta qadam orqaga. BIRINCHI QADAM: orqaga qaytadigan qadam
/// yo'q, ya'ni bosish oqimni tark etish demakdir — shuning uchun tasdiq
/// so'raladi.
VoidCallback bozorStepBack(
  BuildContext context, {
  required bool isFirstStep,
}) => isFirstStep
    ? () => confirmCloseBozorWizard(context)
    : () => Navigator.of(context).maybePop();

/// Qadam sarlavhasidagi × amali — birinchi qadamda tugma umuman chizilmaydi
/// (u yerda ← ning o'zi allaqachon chiqish).
VoidCallback? bozorStepClose(
  BuildContext context, {
  required bool isFirstStep,
}) => isFirstStep ? null : () => confirmCloseBozorWizard(context);
