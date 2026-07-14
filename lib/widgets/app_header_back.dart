import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/haptics.dart';
import '../theme/color_tokens.dart';

/// Standard inner-page header: leading 40dp white circle with a default
/// arrow.svg (or custom SVG) back button, centered title in MTSCompact,
/// and an optional trailing widget (kept symmetric with the leading slot).
class AppHeaderBack extends StatelessWidget {
  static const String defaultBackIconAsset = 'assets/icons/arrow.svg';

  const AppHeaderBack({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.backIconAsset,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String? backIconAsset;

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
              iconAsset: backIconAsset,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.2,
              color: ColorTokens.primaryText(context),
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
  const _BackButton({required this.onTap, this.iconAsset});

  final VoidCallback onTap;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: hapticTap(onTap),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: ColorTokens.cardBg(context),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: ColorTokens.shadow(context),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            iconAsset ?? AppHeaderBack.defaultBackIconAsset,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              ColorTokens.primaryText(context),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}
