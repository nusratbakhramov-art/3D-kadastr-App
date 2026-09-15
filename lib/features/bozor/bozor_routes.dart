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
