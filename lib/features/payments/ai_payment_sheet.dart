import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/payment_deep_links.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../market/widgets/listing_cta_button.dart';
import 'payment_checkout_service.dart';

/// AI Baholash arizasi to'lov bottom-sheet'i.
///
/// Summani backenddan ([PaymentCheckoutService.getQuote]) oladi, to'lov usuli
/// tanlanadi (Payme — default; Click — hozircha "tez orada", disabled), "To'lash"
/// bosilganda Payme checkout URL generate qilinib tashqi ilovada ochiladi.
Future<void> showAiPaymentSheet(
  BuildContext context, {
  int? referenceId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiPaymentSheet(referenceId: referenceId),
  );
}

enum _PayMethod { payme, click }

class _AiPaymentSheet extends StatefulWidget {
  const _AiPaymentSheet({this.referenceId});

  final int? referenceId;

  @override
  State<_AiPaymentSheet> createState() => _AiPaymentSheetState();
}

class _AiPaymentSheetState extends State<_AiPaymentSheet> {
  final PaymentCheckoutService _service = PaymentCheckoutService();

  PaymentQuote? _quote;
  String? _quoteError;
  bool _loadingQuote = true;
  bool _paying = false;
  _PayMethod _method = _PayMethod.payme; // Payme default-selected.

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _loadingQuote = true;
      _quoteError = null;
    });
    try {
      final q = await _service.getQuote(PaymentCheckoutService.aiValuationType);
      if (!mounted) return;
      setState(() {
        _quote = q;
        _loadingQuote = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteError = '$e';
        _loadingQuote = false;
      });
    }
  }

  Future<void> _pay() async {
    final q = _quote;
    if (q == null || _paying) return;
    HapticFeedback.lightImpact();
    setState(() => _paying = true);
    try {
      // Hozircha faqat Payme yoqilgan.
      final r = await _service.initiate(
        paymentType: PaymentCheckoutService.aiValuationType,
        provider: 'payme',
        amount: q.amount,
        referenceType: 'ai_valuation_job',
        referenceId: widget.referenceId,
      );
      if (!mounted) return;
      // App fonдан qaytganda natija ekrani ochilishi uchun id'ni eslab qolamiz.
      PaymentDeepLinks.pendingPaymentId = r.paymentId;
      final ok =
          await launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() => _paying = false);
      if (ok) {
        Navigator.of(context).pop();
      } else {
        AppToast.error(context, _S.openFailed(Localizations.localeOf(context)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
      AppToast.error(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF14181A) : Colors.white;
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        // Clear the home-indicator/gesture bar (viewPadding.bottom) + keyboard
        // (viewInsets.bottom) with a 16px margin, so the pay button is never cut
        // off at the bottom on gesture-nav devices.
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          16 +
              MediaQuery.viewPaddingOf(context).bottom +
              MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sub.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _S.title(l),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _S.subtitle(l),
              style: TextStyle(fontFamily: 'MTSText', fontSize: 13, color: sub),
            ),
            const SizedBox(height: 18),
            _AmountBlock(
              quote: _quote,
              loading: _loadingQuote,
              error: _quoteError,
              onRetry: _loadQuote,
              isDark: isDark,
              locale: l,
            ),
            const SizedBox(height: 18),
            Text(
              _S.method(l),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: sub,
              ),
            ),
            const SizedBox(height: 10),
            _MethodTile(
              label: 'Payme',
              selected: _method == _PayMethod.payme,
              enabled: true,
              isDark: isDark,
              onTap: () => setState(() => _method = _PayMethod.payme),
            ),
            const SizedBox(height: 8),
            _MethodTile(
              label: 'Click',
              selected: false,
              enabled: false,
              isDark: isDark,
              badge: _S.soon(l),
              onTap: null,
            ),
            const SizedBox(height: 22),
            _paying
                ? const _PayingButton()
                : ListingCtaButton(
                    label: _S.pay(l),
                    enabled: _quote != null,
                    onTap: _pay,
                  ),
          ],
        ),
      ),
    );
  }
}

class _AmountBlock extends StatelessWidget {
  const _AmountBlock({
    required this.quote,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.isDark,
    required this.locale,
  });

  final PaymentQuote? quote;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : const Color(0xFFF1F3F5);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    Widget body;
    if (loading) {
      body = Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.splashGreen),
          ),
          const SizedBox(width: 10),
          Text(_S.loadingAmount(locale),
              style: TextStyle(fontFamily: 'MTSText', fontSize: 13, color: sub)),
        ],
      );
    } else if (quote == null) {
      body = Row(
        children: [
          Expanded(
            child: Text(_S.amountError(locale),
                style: const TextStyle(
                    fontFamily: 'MTSText', fontSize: 13, color: Color(0xFFE0492A))),
          ),
          TextButton(onPressed: onRetry, child: Text(_S.retry(locale))),
        ],
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatAmount(quote!.amount),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w900,
              fontSize: 26,
              color: text,
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(_S.soum(locale),
                style: TextStyle(
                    fontFamily: 'MTSText', fontSize: 14, color: sub)),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_S.amountLabel(locale),
              style: TextStyle(fontFamily: 'MTSText', fontSize: 12, color: sub)),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }

  static String _formatAmount(num v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.isDark,
    this.badge,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final bool isDark;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = selected
        ? AppColors.splashGreen
        : (isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8));
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: selected ? 1.6 : 1),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 22,
                  color: selected ? AppColors.splashGreen : sub,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: text,
                  ),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sub.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: sub,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PayingButton extends StatelessWidget {
  const _PayingButton();
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.splashGreen.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(999),
      child: const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.buttonTextBlack),
            ),
          ),
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
        'ru' => 'Подача заявки',
        'en' => 'Submit application',
        _ => 'Ariza yuborish',
      };

  static String subtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Оплатите, чтобы оформить официальную заявку',
        'en' => 'Pay to submit the official application',
        _ => 'Rasmiy arizani rasmiylashtirish uchun to\'lov qiling',
      };

  static String amountLabel(Locale l) => switch (l.languageCode) {
        'ru' => 'Сумма к оплате',
        'en' => 'Amount due',
        _ => 'To\'lov summasi',
      };

  static String method(Locale l) => switch (l.languageCode) {
        'ru' => 'Способ оплаты',
        'en' => 'Payment method',
        _ => 'To\'lov usuli',
      };

  static String soon(Locale l) => switch (l.languageCode) {
        'ru' => 'скоро',
        'en' => 'soon',
        _ => 'tez orada',
      };

  static String pay(Locale l) => switch (l.languageCode) {
        'ru' => 'Оплатить',
        'en' => 'Pay',
        _ => 'To\'lash',
      };

  static String soum(Locale l) => switch (l.languageCode) {
        'ru' => 'сум',
        'en' => 'soum',
        _ => 'so\'m',
      };

  static String loadingAmount(Locale l) => switch (l.languageCode) {
        'ru' => 'Загрузка суммы...',
        'en' => 'Loading amount...',
        _ => 'Summa yuklanmoqda...',
      };

  static String amountError(Locale l) => switch (l.languageCode) {
        'ru' => 'Не удалось получить сумму',
        'en' => 'Could not load the amount',
        _ => 'Summani olib bo\'lmadi',
      };

  static String retry(Locale l) => switch (l.languageCode) {
        'ru' => 'Повторить',
        'en' => 'Retry',
        _ => 'Qayta urinish',
      };

  static String openFailed(Locale l) => switch (l.languageCode) {
        'ru' => 'Не удалось открыть Payme',
        'en' => 'Could not open Payme',
        _ => 'Payme ochilmadi',
      };
}
