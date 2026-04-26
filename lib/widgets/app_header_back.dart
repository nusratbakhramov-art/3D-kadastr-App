import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Standard inner-page header: leading 40dp white circle with a black
/// chevron-left back button, centered title in MTSCompact, and an optional
/// trailing widget (kept symmetric with the leading slot).
class AppHeaderBack extends StatelessWidget {
  const AppHeaderBack({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackButton(
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.2,
              color: AppColors.textBlack,
            ),
          ),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.chevron_left_rounded,
            size: 22,
            color: AppColors.textBlack,
          ),
        ),
      ),
    );
  }
}
