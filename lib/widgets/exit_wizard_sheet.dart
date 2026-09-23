/// Ko'p qadamli oqimdan chiqishni tasdiqlovchi pastki DRAWER.
///
/// Ikki sehrgar ham (Bozor AI va AI Baholash) shu yerdan foydalanadi: oyna
/// bitta bo'lsa, ikkalasida ham bir xil ko'rinadi va bir joyda tuzatiladi.
/// Faqat matnlar har xil — oqimlar boshqa narsani tark etadi.
///
/// Material `AlertDialog` ATAYLAB ishlatilmaydi: u ilovaning tipografiyasi,
/// radiusi va tugmalaridan butunlay boshqacha ko'rinadi — bitta o'zi qolgan
/// hamma oynadan (`login_required_sheet`, `no_internet_sheet`,
/// `pano_source_sheet`…) ajralib turardi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'sheet_button.dart';

/// Tasdiq oynasi hozir ochiqmi — [confirmLeaveWizard] ga qarang.
bool _confirming = false;

/// Chiqishni so'raydi va javobni qaytaradi.
///
/// ⚠️ BITTA MAROTABA. Chaqiruv qulflangan: tugma ikki marta tez bosilsa (yoki
/// tizimning «orqaga» si drawer ochiq turganda yana kelsa) ikkita bir xil oyna
/// ustma-ust chiqib, birinchisini yopish ikkinchisini ochiq qoldirardi —
/// foydalanuvchi bir xil savolga ikki marta javob berardi.
///
/// Qaytadi: foydalanuvchi chiqishni tasdiqladimi. Oqimni YOPISH chaqiruvchining
/// zimmasida — har bir sehrgar o'zicha yopiladi.
Future<bool> confirmLeaveWizard(
  BuildContext context, {
  required String title,
  required String body,
  required String stayLabel,
  required String leaveLabel,
}) async {
  if (_confirming) return false;
  _confirming = true;
  try {
    HapticFeedback.mediumImpact();
    final leave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExitWizardSheet(
        title: title,
        body: body,
        stayLabel: stayLabel,
        leaveLabel: leaveLabel,
      ),
    );
    return leave == true;
  } finally {
    _confirming = false;
  }
}

/// Tugmalar tartibi ataylab shunday: XAVFSIZ amal (oqimda qolish) — asosiy,
/// yashil va tepada; chiqish esa ostida, `destructive` (qizil tonal)
/// ko'rinishda. Chiqish qaytarib bo'lmaydigan amal emas — qoralama saqlanib
/// qoladi — lekin u boshlangan ishni tark etadi, shuning uchun tasodifan
/// bosilmasligi kerak.
class _ExitWizardSheet extends StatelessWidget {
  const _ExitWizardSheet({
    required this.title,
    required this.body,
    required this.stayLabel,
    required this.leaveLabel,
  });

  final String title;
  final String body;
  final String stayLabel;
  final String leaveLabel;

  @override
  Widget build(BuildContext context) {
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
                title,
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
                body,
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
                label: stayLabel,
                filled: true,
                isDark: isDark,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop(false);
                },
              ),
              const SizedBox(height: 10),
              SheetButton(
                label: leaveLabel,
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
