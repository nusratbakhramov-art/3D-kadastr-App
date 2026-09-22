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
import 'package:flutter/services.dart';

import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../widgets/sheet_button.dart';

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
/// Pastki DRAWER — ilovaning qolgan hamma so'rov oynalari kabi
/// (`login_required_sheet`, `no_internet_sheet`, `pano_source_sheet`…).
/// Material `AlertDialog` ATAYLAB ishlatilmaydi: u ilovaning tipografiyasi,
/// radiusi va tugmalaridan butunlay boshqacha ko'rinadi — bitta o'zi qolgan
/// hamma oynadan ajralib turardi.
///
/// ⚠️ BITTA MAROTABA. Chaqiruv `_confirmingExit` bilan qulflangan: tugma ikki
/// marta tez bosilsa (yoki tizim «orqaga» si drawer ochiq turganda yana kelsa)
/// ikkita bir xil oyna ustma-ust chiqib, birinchisini yopish ikkinchisini
/// ochiq qoldirardi — foydalanuvchi bir xil savolga ikki marta javob berardi.
///
/// Qaytadi: foydalanuvchi chiqishni tasdiqladimi.
Future<bool> confirmCloseBozorWizard(BuildContext context) async {
  if (_confirmingExit) return false;
  _confirmingExit = true;
  try {
    HapticFeedback.mediumImpact();
    final leave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExitWizardSheet(),
    );
    if (leave != true || !context.mounted) return false;
    closeBozorWizard(context);
    return true;
  } finally {
    _confirmingExit = false;
  }
}

/// «E'lonni bekor qilmoqchimisiz?» drawer'i.
///
/// Tugmalar tartibi ataylab shunday: XAVFSIZ amal (oqimda qolish) — asosiy,
/// yashil va tepada; chiqish esa ostida, `destructive` (qizil tonal)
/// ko'rinishda. Chiqish qaytarib bo'lmaydigan amal emas — qoralama saqlanib
/// qoladi — lekin u boshlangan ishni tark etadi, shuning uchun tasodifan
/// bosilmasligi kerak.
class _ExitWizardSheet extends StatelessWidget {
  const _ExitWizardSheet();

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    // Rangli konteyner TASHQARIDA: shunda fon pastki xavfsiz zonani (home
    // indikatori yo'lagini) ham to'ldiradi. Teskarisi qilinsa o'sha yo'lakda
    // qorong'i pardaning o'zi ko'rinib qolardi — `login_required_sheet` dagi
    // bilan bir xil sabab.
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C3133)
                      : const Color(0xFFE3E5E8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.declineRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  size: 26,
                  color: AppColors.declineRed,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr(l, 'bozor.exit.title'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(l, 'bozor.exit.body'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 14,
                  height: 1.4,
                  color: muted,
                ),
              ),
              const SizedBox(height: 24),
              SheetButton(
                label: tr(l, 'bozor.exit.stay'),
                filled: true,
                isDark: isDark,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop(false);
                },
              ),
              const SizedBox(height: 10),
              SheetButton(
                label: tr(l, 'bozor.exit.leave'),
                destructive: true,
                isDark: isDark,
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
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
