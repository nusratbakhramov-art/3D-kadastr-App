import 'package:flutter/material.dart';

class HomeCta extends StatelessWidget {
  const HomeCta({
    super.key,
    required this.isGuest,
    required this.locale,
    this.onOrderTap,
    this.onLoginTap,
  });

  final bool isGuest;
  final Locale locale;
  final VoidCallback? onOrderTap;
  final VoidCallback? onLoginTap;

  @override
  Widget build(BuildContext context) {
    final label = isGuest
        ? _CtaStrings.loginLabel(locale)
        : _CtaStrings.orderLabel(locale);
    final onTap = isGuest ? onLoginTap : onOrderTap;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 148,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/home/cta-bg.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
            Positioned(
              right: -8,
              top: 0,
              bottom: 0,
              child: Image.asset(
                'assets/images/home/cta-icon.png',
                height: 148,
                fit: BoxFit.fitHeight,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 220,
                    child: Text(
                      _CtaStrings.headline(locale),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        height: 1.3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _CtaButton(label: label, onTap: onTap),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.2,
                  color: Color(0xFF151515),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: Color(0xFF151515),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaStrings {
  const _CtaStrings._();

  static String headline(Locale locale) => switch (locale.languageCode) {
    'ru' => 'Расчёт комплексных услуг',
    'en' => 'Estimate complex services',
    _ => 'Kompleks xizmatlarini hisoblash',
  };

  static String orderLabel(Locale locale) => switch (locale.languageCode) {
    'ru' => 'Онлайн калькулятор',
    'en' => 'Online calculator',
    _ => 'Online kalkulyator',
  };

  static String loginLabel(Locale locale) => switch (locale.languageCode) {
    'ru' => 'Войти',
    'en' => 'Log in',
    _ => 'Kirish',
  };
}
