import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/color_tokens.dart';
import 'circle_chevron_right.dart';
import 'pressable_scale.dart';

/// Rounded card that hosts a vertical list of [AppMenuRow]s separated by
/// hairline dividers. Background and divider colors adapt to the active theme.
class AppMenuCard extends StatelessWidget {
  const AppMenuCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final dividerColor = ColorTokens.divider(context);
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    );
  }
}

/// A row inside an [AppMenuCard]: 32dp leading icon (SVG asset or Material
/// icon), label, and a 20dp black-circle chevron-right by default.
///
/// Set [destructive] to render the label in red and replace the trailing
/// chevron with nothing — used for logout-style rows.
class AppMenuRow extends StatelessWidget {
  const AppMenuRow({
    super.key,
    this.iconAsset,
    this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
    this.trailing,
  }) : assert(
         iconAsset != null || icon != null,
         'Provide either iconAsset or icon.',
       );

  final String? iconAsset;
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final labelColor = destructive
        ? const Color(0xFFE5484D)
        : ColorTokens.primaryText(context);

    final leading = iconAsset != null
        ? SvgPicture.asset(iconAsset!, width: 32, height: 32)
        : Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: ColorTokens.iconBg(context),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: labelColor),
          );

    final trailingWidget =
        trailing ??
        (destructive ? const SizedBox.shrink() : const CircleChevronRight());

    return PressableScale(
      enabled: onTap != null,
      pressedScale: 0.985,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    height: 1.2,
                    color: labelColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              trailingWidget,
            ],
          ),
          ),
        ),
      ),
    );
  }
}
