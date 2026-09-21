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
/// ⚠️ BITTA MAROTABA. Dialog chaqiruvi `_confirmingExit` bilan qulflangan:
/// tugma ikki marta tez bosilsa (yoki tizim «orqaga» si dialog ochiq turganda
/// yana kelsa) ikkita bir xil oyna ustma-ust chiqib, birinchisini yopish
/// ikkinchisini ochiq qoldirardi — foydalanuvchi bir xil savolga ikki marta
/// javob berardi.
///
/// Qaytadi: foydalanuvchi chiqishni tasdiqladimi.
Future<bool> confirmCloseBozorWizard(BuildContext context) async {
  if (_confirmingExit) return false;
  _confirmingExit = true;
  final l = Localizations.localeOf(context);
  try {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(l, 'bozor.exit.title')),
        content: Text(tr(l, 'bozor.exit.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(l, 'bozor.exit.stay')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(l, 'bozor.exit.leave')),
          ),
        ],
      ),
    );
    if (leave != true || !context.mounted) return false;
    closeBozorWizard(context);
    return true;
  } finally {
    _confirmingExit = false;
  }
}

/// Tasdiq oynasi hozir ochiqmi — [confirmCloseBozorWizard] ga qarang.
bool _confirmingExit = false;

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
