import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

class ResendTimer extends StatefulWidget {
  const ResendTimer({
    super.key,
    required this.onResend,
    this.duration = const Duration(seconds: 90),
  });

  final VoidCallback onResend;
  final Duration duration;

  @override
  State<ResendTimer> createState() => _ResendTimerState();
}

class _ResendTimerState extends State<ResendTimer> {
  Timer? _timer;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _remaining = widget.duration.inSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) _remaining--;
        if (_remaining == 0) _timer?.cancel();
      });
    });
  }

  void _handleResend() {
    widget.onResend();
    setState(_start);
  }

  String _format(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final timerBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final timerFg = isDark
        ? Colors.white70
        : AppColors.textBlack.withValues(alpha: 0.65);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _ResendTimerStrings.label(locale),
          style: TextStyle(
            color: titleColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        if (_remaining > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: timerBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _format(_remaining),
              style: TextStyle(
                color: timerFg,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          Material(
            key: const ValueKey('resend.button'),
            color: AppColors.splashGreen,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: hapticTap(_handleResend),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.refresh, color: Colors.black, size: 18),
              ),
            ),
          ),
      ],
    );
  }
}

class _ResendTimerStrings {
  const _ResendTimerStrings._();

  static String label(Locale l) => switch (l.languageCode) {
    'ru' => 'Отправить снова',
    'en' => 'Resend',
    _ => 'Qayta yuborish',
  };
}
