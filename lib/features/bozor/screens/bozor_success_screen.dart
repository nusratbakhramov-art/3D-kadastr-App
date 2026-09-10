/// E'lon yuborilgandan keyingi ekran.
///
/// Dizaynda sarlavha, katta yashil belgi va ikkita tugma bor; orqaga tugmasi
/// YO'Q — bu yerga faqat oldinga kelinadi, shuning uchun oqim [pushAndRemoveUntil]
/// bilan almashtiriladi.
///
/// Belgi dizaynda Lottie animatsiyasi sifatida belgilangan (Figma'dagi
/// «lottie» yorlig'i). `lottie` paketi ilovada YO'Q va uni Figma qatlamidagi
/// izohga qarab qo'shmadim — buning o'rniga bir martalik masshtab+shaffoflik
/// animatsiyasi, ilovaning boshqa joylaridagidek. Haqiqiy Lottie kerak bo'lsa
/// bu alohida qaror.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../listings/my_listings_screen.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../bozor_routes.dart';
import '../models/bozor_draft.dart';
import 'bozor_type_step_screen.dart';

class BozorSuccessScreen extends StatelessWidget {
  const BozorSuccessScreen({super.key});

  /// TODO(backend): e'lon yaratish endpoint'i bo'lmagani uchun yangi e'lonning
  /// id'si yo'q — "nashrga o'tish" hozircha o'z e'lonlarim ro'yxatini ochadi.
  void _openPublication(BuildContext context) {
    closeBozorWizard(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MyListingsScreen()),
    );
  }

  /// Yangi e'lon — YANGI qoralama bilan. Eskisini qayta ishlatib bo'lmaydi:
  /// parametrlar, rasm yo'llari va telefonlar keyingi e'longa o'tib ketardi.
  void _addAnother(BuildContext context) {
    closeBozorWizard(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('type'),
        builder: (_) => BozorTypeStepScreen(draft: BozorDraft()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return PopScope(
      // Orqaga qaytish yo'q: sehrgar allaqachon yopilgan.
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final maxContent = c.maxWidth.clamp(0.0, 640.0);
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContent),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      children: [
                        const Spacer(),
                        const _AnimatedCheck(),
                        const SizedBox(height: 28),
                        Text(
                          tr(l, 'bozor.success.title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            height: 1.3,
                            color: textColor,
                          ),
                        ),
                        const Spacer(),
                        ListingCtaButton(
                          label: tr(l, 'bozor.success.go_to_listing'),
                          onTap: () => _openPublication(context),
                        ),
                        const SizedBox(height: 10),
                        _SecondaryButton(
                          label: tr(l, 'bozor.success.add_another'),
                          onTap: () => _addAnother(context),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Bir martalik masshtab + shaffoflik animatsiyasi — Lottie o'rniga.
class _AnimatedCheck extends StatelessWidget {
  const _AnimatedCheck();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        // easeOutBack oshib ketadi — shaffoflik 1 dan oshmasin.
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: t, child: child),
      ),
      child: Container(
        width: 124,
        height: 124,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.splashGreen,
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 68,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Ikkilamchi tugma — [ListingCtaButton] bilan bir o'lchamda, lekin yashil
/// emas: ekranda asosiy harakat bitta bo'lishi kerak.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
