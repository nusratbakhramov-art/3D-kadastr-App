import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/app_colors.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.iconAsset,
    required this.body,
    required this.onSkip,
    this.onBack,
    this.bottom,
  });

  final String title;
  final String iconAsset;
  final Widget body;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final backgroundColor = isDark
        ? AppColors.greenBlack
        : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onBack: onBack, onSkip: onSkip),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [_IconBadge(asset: iconAsset)]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                  ).copyWith(color: titleColor),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: body,
              ),
            ),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onSkip});

  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        children: [
          if (onBack != null)
            _CircleIconButton(
              key: const ValueKey('auth.back'),
              iconAsset: 'assets/icons/arrow.svg',
              onPressed: onBack!,
            )
          else
            const SizedBox(width: 40, height: 40),
          const Spacer(),
          _SkipButton(key: const ValueKey('auth.skip'), onPressed: onSkip),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    super.key,
    this.icon,
    this.iconAsset,
    required this.onPressed,
  }) : assert(
         icon != null || iconAsset != null,
         'Either icon or iconAsset must be provided.',
       );

  final IconData? icon;
  final String? iconAsset;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: iconAsset != null
                ? SvgPicture.asset(
                    iconAsset!,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  )
                : Icon(icon, color: fg, size: 20),
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "O'tkazib yuborish",
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, color: fg, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(asset, width: 56, height: 56, fit: BoxFit.contain);
  }
}
