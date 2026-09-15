import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';

class AppBottomNavItem {
  const AppBottomNavItem({
    required this.label,
    required this.iconAsset,
    this.tintLight,
    this.tintDark,
  });

  final String label;
  final String iconAsset;

  /// Colour the glyph is painted in, or null to let the asset paint itself.
  ///
  /// Market and Arizalar carry the korzinka.uz and my.gov.uz marks, which have
  /// their own brand palettes — those tabs leave both tints null so the logos
  /// come through untouched. Asosiy and Profil are single-colour glyphs, and
  /// they do need the two values: the nav sits on white in light mode and on
  /// [AppColors.greenBlack] in dark, so a black profile icon would vanish.
  final Color? tintLight;
  final Color? tintDark;
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onChanged,
  });

  final int currentIndex;
  final List<AppBottomNavItem> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppColors.greenBlack
        : const Color(0xFFFEFEFE);

    return Container(
      color: backgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTab(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppBottomNavItem item;

  /// Carried for semantics only. The tabs are deliberately not styled by
  /// selection — every icon keeps its own fixed colour — but a screen reader
  /// still has to be able to announce which tab the user is on.
  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark ? item.tintDark : item.tintLight;
    final labelColor = isDark
        ? AppColors.darkTextSecondary
        : const Color(0xFF6B7073);

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hapticSelect(onTap),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  item.iconAsset,
                  width: 26,
                  height: 26,
                  colorFilter: tint == null
                      ? null
                      : ColorFilter.mode(tint, BlendMode.srcIn),
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    height: 1.2,
                    color: labelColor,
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
