/// TZ / kalkulyator buyurtmasi muvaffaqiyatli yuborilgandan keyingi ekran.
/// Dizayn, arxitektura va oddiy kalkulyator arizalari uchun umumiy.
library;

import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';

String _pick(Locale l, {required String uz, required String ru, required String en}) {
  switch (l.languageCode) {
    case 'ru':
      return ru;
    case 'en':
      return en;
    default:
      return uz;
  }
}

class ArxitekturaTzSuccessScreen extends StatelessWidget {
  const ArxitekturaTzSuccessScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF6B7280);
    final locale = Localizations.localeOf(context);

    final title = _pick(
      locale,
      uz: 'Buyurtma qabul qilindi',
      ru: 'Заявка принята',
      en: 'Order received',
    );
    final body = _pick(
      locale,
      uz: 'Buyurtma raqami: #$orderId\n\n'
          'Mutaxassislarimiz tez orada siz bilan bog\'lanib, '
          'narx va shartlarni tasdiqlaydi.',
      ru: 'Номер заявки: #$orderId\n\n'
          'Наши специалисты свяжутся с вами в ближайшее время '
          'и подтвердят стоимость и условия.',
      en: 'Order number: #$orderId\n\n'
          'Our specialists will contact you shortly to confirm '
          'the price and terms.',
    );
    final buttonLabel = _pick(
      locale,
      uz: 'Asosiy ekranga',
      ru: 'На главный экран',
      en: 'To home',
    );

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.splashGreen.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.splashGreen,
                        size: 56,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 14,
                      height: 1.5,
                      color: hintColor,
                    ),
                  ),
                  const Spacer(),
                  ListingCtaButton(
                    label: buttonLabel,
                    enabled: true,
                    onTap: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
