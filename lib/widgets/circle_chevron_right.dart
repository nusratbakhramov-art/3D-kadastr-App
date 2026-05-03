import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/color_tokens.dart';

class CircleChevronRight extends StatelessWidget {
  const CircleChevronRight({
    super.key,
    this.size = 20,
    this.padding = 2,
    this.iconSize = 16,
    this.backgroundColor,
  });

  final double size;
  final double padding;
  final double iconSize;

  /// When null, resolves to the theme's primary text color (dark in light
  /// mode, white in dark mode) so the chevron always contrasts the page bg.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? ColorTokens.primaryText(context);
    final fg = ColorTokens.cardBg(context);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(1000),
      ),
      child: SvgPicture.asset(
        'assets/icons/chevron-right.svg',
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
      ),
    );
  }
}
