import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/app_colors.dart';
import '../models/payment_method.dart';

class ListingPaymentCard extends StatelessWidget {
  const ListingPaymentCard({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121617) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark ? null : Border.all(color: const Color(0xFFE3E5E8));

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: border,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To\'lov',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.3,
              color: fg,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Option(
                  method: PaymentMethod.payme,
                  selected: selected == PaymentMethod.payme,
                  onTap: () => _select(PaymentMethod.payme),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Option(
                  method: PaymentMethod.uzum,
                  selected: selected == PaymentMethod.uzum,
                  onTap: () => _select(PaymentMethod.uzum),
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Option(
                  method: PaymentMethod.click,
                  selected: selected == PaymentMethod.click,
                  onTap: () => _select(PaymentMethod.click),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Option(
                  method: PaymentMethod.paynet,
                  selected: selected == PaymentMethod.paynet,
                  onTap: () => _select(PaymentMethod.paynet),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _select(PaymentMethod m) {
    if (m == selected) return;
    HapticFeedback.selectionClick();
    onChanged(m);
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.method,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2C3133)
        : const Color(0xFFE3E5E8);
    final idleRadioColor = isDark
        ? const Color(0xFF3A4042)
        : const Color(0xFFD1D5D9);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                method.assetPath,
                height: method.renderHeight,
                fit: BoxFit.fitHeight,
              ),
              const Spacer(),
              _Radio(selected: selected, idleColor: idleRadioColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected, required this.idleColor});

  final bool selected;
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.splashGreen : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.splashGreen : idleColor,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}
