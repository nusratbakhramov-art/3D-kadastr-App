import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'payment_checkout_service.dart';

/// To'lovdan keyin appga qaytganda (iOS Universal Link `/pay-return/{id}`)
/// ochiladi: to'lov holatini backenddan polling qilib ko'rsatadi
/// (PENDING → kutilmoqda, COMPLETED → muvaffaqiyat).
class PaymentResultScreen extends StatefulWidget {
  const PaymentResultScreen({super.key, required this.paymentId});

  final int paymentId;

  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

enum _Stage { checking, success, pending, failed }

class _PaymentResultScreenState extends State<PaymentResultScreen> {
  final PaymentCheckoutService _service = PaymentCheckoutService();
  _Stage _stage = _Stage.checking;
  Timer? _poll;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _check();
    // Webhook biroz kechikishi mumkin — 3s da bir, 20 marta (~1 daqiqa) poll.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    _attempts++;
    final status = await _service.getStatus(widget.paymentId);
    if (!mounted) return;
    if (status == 'completed') {
      _poll?.cancel();
      setState(() => _stage = _Stage.success);
    } else if (status == 'failed' || status == 'cancelled') {
      _poll?.cancel();
      setState(() => _stage = _Stage.failed);
    } else if (_attempts >= 20) {
      // Hali PENDING — webhook kechikkan bo'lishi mumkin; foydalanuvchi keyin
      // "Arizalarim"dan ko'radi.
      _poll?.cancel();
      setState(() => _stage = _Stage.pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final (IconData icon, Color color, String title, String body) content =
        switch (_stage) {
      _Stage.checking => (
          Icons.hourglass_top_rounded,
          AppColors.splashGreen,
          _S.checking(l),
          _S.checkingBody(l),
        ),
      _Stage.success => (
          Icons.check_circle_rounded,
          AppColors.splashGreen,
          _S.success(l),
          _S.successBody(l),
        ),
      _Stage.pending => (
          Icons.schedule_rounded,
          const Color(0xFFF27523),
          _S.pending(l),
          _S.pendingBody(l),
        ),
      _Stage.failed => (
          Icons.error_outline_rounded,
          const Color(0xFFE0492A),
          _S.failed(l),
          _S.failedBody(l),
        ),
    };

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_stage == _Stage.checking)
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const SizedBox(
                            width: 84,
                            height: 84,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.splashGreen),
                            ),
                          ),
                          Icon(content.$1, size: 40, color: content.$2),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: content.$2.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(content.$1, size: 44, color: content.$2),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    content.$3,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    content.$4,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 14,
                      height: 1.4,
                      color: subColor,
                    ),
                  ),
                  if (_stage != _Stage.checking) ...[
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: AppColors.splashGreen,
                        borderRadius: BorderRadius.circular(999),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            // Muvaffaqiyatда oqimdan TOZA chiqamiz (asosiy
                            // ekranga) — ariza/natija ekranida qoldirib qo'ymaymiz
                            // (qayta to'lash tugmasi bilan "qolib ketish" oldini
                            // oladi). Pending/failed — shunchaki yopiladi.
                            if (_stage == _Stage.success) {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            } else {
                              Navigator.of(context).maybePop();
                            }
                          },
                          child: SizedBox(
                            height: 52,
                            child: Center(
                              child: Text(
                                _S.done(l),
                                style: const TextStyle(
                                  fontFamily: 'MTSCompact',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String checking(Locale l) => switch (l.languageCode) {
        'ru' => 'Проверяем оплату…',
        'en' => 'Checking payment…',
        _ => 'To\'lov tekshirilmoqda…',
      };
  static String checkingBody(Locale l) => switch (l.languageCode) {
        'ru' => 'Подтверждаем статус оплаты, это займёт пару секунд.',
        'en' => 'Confirming the payment status, this takes a few seconds.',
        _ => 'To\'lov holati tasdiqlanmoqda, bir necha soniya.',
      };
  static String success(Locale l) => switch (l.languageCode) {
        'ru' => 'Оплата прошла успешно',
        'en' => 'Payment successful',
        _ => 'To\'lov muvaffaqiyatli',
      };
  static String successBody(Locale l) => switch (l.languageCode) {
        'ru' => 'Спасибо! Заявка оплачена и принята в обработку.',
        'en' => 'Thank you! Your application is paid and being processed.',
        _ => 'Rahmat! Ariza to\'landi va qayta ishlashga qabul qilindi.',
      };
  static String pending(Locale l) => switch (l.languageCode) {
        'ru' => 'Оплата обрабатывается',
        'en' => 'Payment is processing',
        _ => 'To\'lov qayta ishlanmoqda',
      };
  static String pendingBody(Locale l) => switch (l.languageCode) {
        'ru' => 'Это может занять минуту. Статус появится в «Заявках».',
        'en' => 'This may take a minute. Status will appear in “Applications”.',
        _ => 'Bu bir daqiqa olishi mumkin. Holat «Arizalar»da ko\'rinadi.',
      };
  static String failed(Locale l) => switch (l.languageCode) {
        'ru' => 'Оплата не завершена',
        'en' => 'Payment not completed',
        _ => 'To\'lov yakunlanmadi',
      };
  static String failedBody(Locale l) => switch (l.languageCode) {
        'ru' => 'Оплата отменена или не прошла. Попробуйте ещё раз.',
        'en' => 'The payment was cancelled or failed. Please try again.',
        _ => 'To\'lov bekor qilindi yoki o\'tmadi. Qayta urinib ko\'ring.',
      };
  static String done(Locale l) => switch (l.languageCode) {
        'ru' => 'Готово',
        'en' => 'Done',
        _ => 'Tayyor',
      };
}
