import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';

class AppBottomNavItem {
  const AppBottomNavItem({
    required this.label,
    required this.iconAsset,
    required this.labelColorLight,
    required this.labelColorDark,
    this.iconBuilder,
  });

  final String label;

  /// Full-colour 3D glyph (PNG). Unlike the old flat SVG tabs these carry their
  /// own palette — green house, blue bag, orange document — so nothing tints
  /// them, and the label below simply repeats the glyph's hue.
  final String iconAsset;

  /// Label colour per theme. It is fixed per tab, not per selection: the design
  /// identifies a tab by its colour, so recolouring on tap would erase the very
  /// cue the user navigates by. Selection is carried to screen readers through
  /// [Semantics] instead.
  final Color labelColorLight;
  final Color labelColorDark;

  /// Replaces [iconAsset] when supplied — Profil paints the user's avatar here,
  /// so the tab shows who is signed in rather than a generic person glyph.
  final WidgetBuilder? iconBuilder;
}

/// The floating tab bar: one rounded white slab lifted off the page, inset from
/// both edges, rather than a full-width strip welded to the bottom of the
/// screen.
///
/// The shell gives its Scaffold `extendBody: true`, so a page's content runs
/// UNDER this bar. What hides it is the gradient behind the slab: transparent
/// at the top, the page's own colour by the bottom. A card scrolling up fades
/// into the background as it passes behind the bar instead of being cut off by
/// a hard edge — which is also why screens reserve [totalHeight] at the end of
/// their scroll, so the last row can still be read.
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

  /// Height of the slab itself, without the padding around it. Home pads its
  /// feed by this plus the gap so the last card clears the bar.
  static const double barHeight = 68;

  /// Height of the fade above the slab. Content scrolling under the bar
  /// dissolves across this band instead of being chopped off at its edge.
  static const double _fadeHeight = 16;

  static const double _gapAboveBar = 6;
  static const double _gapBelowBar = 10;

  /// What a page must keep clear at the bottom so its last row is fully
  /// readable and never touches the slab.
  ///
  /// The bar's own height plus a breathing gap. Two failed attempts are worth
  /// remembering: reserving the slab alone put the support buttons INSIDE the
  /// fade (greyed out), and reserving slab + fade left them resting on the
  /// slab's rounded edge with 8pt between them.
  /// ⚠️ Read from the MediaQuery, NOT from the constants below. With
  /// `extendBody: true` the Scaffold sets `padding.bottom` on the body to this
  /// bar's full height (system inset included), so the page already knows how
  /// much is covered. Adding the constants on top double-counted it: the
  /// support buttons ended up 67pt above the slab with dead background between.
  ///
  /// ⚠️ MANFIY BO'LMAYDI. Klaviatura ochilganda `padding.bottom` nolga tushadi
  /// va ayirma −10 bo'lardi; bu qiymat sahifada `EdgeInsets` ga tushgani uchun
  /// `padding.isNonNegative` tasdiqlashi yiqilib, butun ekran qizil xatoga
  /// aylanardi (iOS simulyatorida kirish ekranida ko'rildi).
  static double contentInset(BuildContext context) =>
      math.max(0, MediaQuery.of(context).padding.bottom - _fadeOverlap);

  /// How far a page's last row may reach INTO the fade band. The top of that
  /// band is fully transparent, so this much overlap costs nothing visually and
  /// it is what closes the last of the gap above the slab.
  static const double _fadeOverlap = 10;

  /// Everything this widget occupies, fade included.
  static double totalHeight(BuildContext context) =>
      _fadeHeight +
      _gapAboveBar +
      barHeight +
      _gapBelowBar +
      MediaQuery.of(context).padding.bottom * 0.4;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slabColor = isDark ? AppColors.darkSurface : Colors.white;
    // The page colour the fade lands on.
    final pageColor = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return DecoratedBox(
      // Transparent at the top, solid page colour by the bottom. The body now
      // extends under this bar, so a card scrolling up passes behind the fade
      // and is gone by the time it reaches the slab — rather than sliding out
      // from under a hard edge.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            pageColor.withValues(alpha: 0),
            pageColor.withValues(alpha: 0.75),
            pageColor,
            pageColor,
          ],
          stops: const [0.0, 0.22, 0.42, 1.0],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          _fadeHeight + _gapAboveBar,
          12,
          _gapBelowBar + MediaQuery.of(context).padding.bottom * 0.4,
        ),
        child: Container(
          height: barHeight,
          // Clipped to its own pill: the selected tab paints a filled pill of its
          // own, and at the first and last tab that fill used to poke out through
          // the slab's rounded corner.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: slabColor,
            borderRadius: BorderRadius.circular(barHeight / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            // Stretch, so each tab's ink fills the slab's height. Row's default
            // centre alignment left every tab only as tall as its own glyph +
            // label, and the ripple came out shorter than the thing tapped.
            crossAxisAlignment: CrossAxisAlignment.stretch,
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

  static const double iconSize = 26;

  /// Inset of the tap target inside its slice of the slab. The ripple and the
  /// selected-tab fill are clipped to this box, so it has to be a pill — a
  /// rounded rectangle here read as a square flashing inside a round bar. The
  /// horizontal inset is the larger of the two: it keeps the end tabs' fill
  /// clear of the slab's own curve.
  /// Kept small on purpose: the ink has to be BIGGER than the glyph and label
  /// it sits under, or the tap reads as landing beside the thing you pressed.
  /// Nothing is painted here while at rest any more, so the only thing these
  /// insets have to do is keep the ripple off the slab's own edge.
  static const double _insetX = 4;
  static const double _insetY = 4;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The LABEL is the indicator. Only the tab you are on has its label in the
    // tab's own hue — green Asosiy, blue Market, orange Arizalar; the rest read
    // as plain dark text. The glyphs keep their full colour either way: they
    // are the artwork, and graying them made the bar look half-broken. Nothing
    // is drawn behind the tab either — a filled pill had to dodge the slab's
    // own corner curve, and it competed with the glyph sitting on it.
    final labelColor = selected
        ? (isDark ? item.labelColorDark : item.labelColorLight)
        : (isDark ? AppColors.darkTextSecondary : const Color(0xFF3A4043));
    // The glyphs are small PNGs; decode them at the size they are drawn at so
    // the bar costs a few KB rather than a full-resolution bitmap per tab.
    final dpr = MediaQuery.of(context).devicePixelRatio;

    final Widget glyph =
        item.iconBuilder?.call(context) ??
        Image.asset(
          item.iconAsset,
          fit: BoxFit.contain,
          cacheWidth: (iconSize * dpr).round(),
          filterQuality: FilterQuality.medium,
        );

    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _insetX,
          vertical: _insetY,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: hapticSelect(onTap),
            customBorder: const StadiumBorder(),
            child: Column(
              // max, not min: the Column is what carries the stretched height
              // down to the Material above it, which is what the ink fills.
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: iconSize, height: iconSize, child: glyph),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  // Design spec: 12/130%, Medium (500), no letter-spacing.
                  // Medium, not semibold — the labels sit under loud 3D glyphs
                  // and a heavier weight made the bar read as all-caps signage.
                  // The selected tab is the one exception.
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                    height: 1.3,
                    letterSpacing: 0,
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
