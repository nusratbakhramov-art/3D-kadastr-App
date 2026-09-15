/// AI Baholash sehrgarining (wizard) navigatsiya elementlari.
///
/// Ikki xil "orqaga" bor va ular ATAYLAB har xil ish qiladi:
///
/// * Yuqoridagi doiraviy tugma ([ServiceAppBar] dagi) — butun oqimni yopadi
///   ([closeAiWizard]). Sakkiz qadamdan sakkiz marta bosib chiqish o'rniga
///   bitta teginishda oqim tark etiladi.
/// * Pastdagi "Ortga qaytish" — bitta qadam orqaga.
///
/// Ilgari ikkalasi ham bir xil ishlardi (bitta qadam orqaga), shuning uchun
/// oqimdan chiqishning tez yo'li umuman yo'q edi.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/pressable_scale.dart';
import '../../market/widgets/listing_cta_button.dart';

/// Butun AI Baholash oqimini yopadi — qadamma-qadam emas, bittada.
///
/// Oqimning HAR BIR marshruti `ai/...` deb nomlangan, shuning uchun nomi
/// `ai/` bilan boshlanmaydigan birinchi marshrutgacha poplaymiz: oqim qayerdan
/// ochilgan bo'lsa (bosh sahifa, xizmatlar ro'yxati yoki draftlar ekrani),
/// o'sha yerga qaytadi.
///
/// DIQQAT: nomsiz marshrut ham to'xtatadi. Oqimga yangi ekran qo'shilganda
/// uning `push` iga `RouteSettings(name: 'ai/...')` berish SHART — aks holda
/// yopish o'sha ekranda to'xtab qoladi.
void closeAiWizard(BuildContext context) {
  Navigator.of(context).popUntil((route) {
    final name = route.settings.name;
    return name == null || !name.startsWith('ai/');
  });
}

/// Qadamning pastki navigatsiyasi: chapda "Ortga", o'ngda asosiy
/// "Davom etish" — qator teng ikkiga bo'linadi.
///
/// Tugmalardan biri bo'lmasa ikkinchisi butun kenglikni egallaydi — pastda
/// yarim bo'sh qator qolmasin:
/// * birinchi qadamda ([onBack] `null`) faqat "Davom etish";
/// * davom etadigan qadam qolmaganda ([onContinue] `null`) faqat "Ortga
///   qaytish".
class WizardNavBar extends StatelessWidget {
  const WizardNavBar({
    super.key,
    this.onBack,
    this.onContinue,
    this.continueLabel,
    this.continueEnabled = true,
    this.backLabel,
    this.onBlockedTap,
  });

  /// `null` — orqaga qaytadigan qadam yo'q, tugma umuman chizilmaydi.
  final VoidCallback? onBack;

  /// `null` — keyingi qadam yo'q, tugma umuman chizilmaydi.
  final VoidCallback? onContinue;

  /// Asosiy tugma matni. Berilmasa — "Davom etish".
  final String? continueLabel;

  /// Asosiy tugma bosiladimi. Forma to'ldirilmagan qadamlar buni `false`
  /// qiladi; "Ortga qaytish" esa HAR DOIM bosiladi — to'ldirilmagan forma
  /// odamni qadamda qamab qo'ymasligi kerak.
  final bool continueEnabled;

  /// Orqaga tugmasi matni. Berilmasa — "Ortga qaytish".
  final String? backLabel;

  /// O'chiq "Davom etish" bosilganda chaqiriladi — nimasi yetishmayotganini
  /// aytish uchun. `null` bo'lsa o'chiq tugma jim turadi.
  final VoidCallback? onBlockedTap;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final back = onBack;
    final next = onContinue;
    final blocked = onBlockedTap;

    Widget? continueButton = next == null
        ? null
        : ListingCtaButton(
            label: continueLabel ?? tr(l, 'services.ai.common.continue'),
            enabled: continueEnabled,
            onTap: next,
          );
    // O'chiq tugma teginishni yutadi, shuning uchun uni tashqi
    // [GestureDetector] ushlaydi: bosgan odam nega o'tolmayotganini bilsin.
    if (continueButton != null && !continueEnabled && blocked != null) {
      continueButton = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: blocked,
        child: continueButton,
      );
    }
    // Yolg'iz turganda to'liq nom sig'adi; "Davom etish" bilan yonma-yon
    // turganda esa qisqasi ishlatiladi — 320pt li ekranda ikkala to'liq nom
    // bitta qatorga sig'masdi (RenderFlex overflow).
    final alone = continueButton == null;
    final backButton = back == null
        ? null
        : _BackButton(
            label: backLabel ??
                tr(l, alone
                    ? 'services.ai.common.back'
                    : 'services.ai.common.back_short'),
            onTap: back,
          );

    if (continueButton == null) return backButton ?? const SizedBox.shrink();
    if (backButton == null) return continueButton;
    // Qator teng ikkiga bo'linadi. Ikkalasi ham [Expanded] — tugmalar
    // matnining uzunligiga qarab sakramaydi, qadamdan qadamga bir xil turadi.
    return Row(
      children: [
        Expanded(child: backButton),
        const SizedBox(width: 10),
        Expanded(child: continueButton),
      ],
    );
  }
}

/// Ikkilamchi uslubdagi tugma — [ListingCtaButton] bilan bir o'lchamda
/// (56 balandlik, to'liq yumaloq), lekin yashil emas: qadamda asosiy harakat
/// bitta bo'lishi kerak.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final fg = isDark ? Colors.white : AppColors.textBlack;

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.arrow_back_rounded, size: 20, color: fg),
        const SizedBox(width: 8),
        // Oxirgi himoya: juda tor ekranda yoki juda uzun tarjimada matn
        // kesiladi, qator esa toshib ketmaydi.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.2,
              color: fg,
            ),
          ),
        ),
      ],
    );

    return PressableScale(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hapticTap(onTap),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: row,
          ),
        ),
      ),
    );
  }
}
