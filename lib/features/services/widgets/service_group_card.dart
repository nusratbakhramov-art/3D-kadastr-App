/// Bir nechta yaqin xizmatni bitta kartaga yig'adigan akkordeon.
///
/// Hozircha "Kadastr hujjatlari" uchun ishlatiladi: oddiy kadastr va 3D kadastr
/// alohida ikkita karta emas, bitta karta ichidagi ikkita qator.
/// Xizmat ro'yxatlarining ikkalasi ham (Onlayn kalkulyator — bitta tanlov,
/// Kadastr oqimi — ko'p tanlov) shu kartani baham ko'radi: qatorning o'ng
/// tomonidagi element (`trailing`) chaqiruvchi ekrandan beriladi.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../theme/app_colors.dart';

class ServiceGroupCard extends StatefulWidget {
  const ServiceGroupCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    this.assetIcon,
    this.iconScale = 1.0,
    this.fallbackIcon = Icons.folder_outlined,
    this.accent = AppColors.splashGreen,
    this.badgeCount = 0,
    this.initiallyExpanded = false,
  });

  final String title;
  final String subtitle;

  /// Akkordeon ichidagi qatorlar — [ServiceGroupRow] bo'lishi kutiladi.
  final List<Widget> rows;

  final String? assetIcon;
  final double iconScale;
  final IconData fallbackIcon;
  final Color accent;

  /// 0 dan katta bo'lsa sarlavhada yashil "n" nishoni chiqadi (ko'p tanlovli
  /// ro'yxatda guruh ichida nechta xizmat tanlanganini ko'rsatish uchun).
  final int badgeCount;

  final bool initiallyExpanded;

  @override
  State<ServiceGroupCard> createState() => _ServiceGroupCardState();
}

class _ServiceGroupCardState extends State<ServiceGroupCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.initiallyExpanded ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _expanded ? _controller.forward() : _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final chevronColor = isDark
        ? Colors.white.withValues(alpha: 0.4)
        : const Color(0xFFB4B9BF);
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFE9EBEE);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: hapticTap(_toggle),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    padding: widget.assetIcon != null
                        ? const EdgeInsets.all(4)
                        : EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: widget.assetIcon != null
                          ? (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFF1F2F4))
                          : widget.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: widget.assetIcon != null
                        ? Transform.scale(
                            scale: widget.iconScale,
                            child: Image.asset(
                              widget.assetIcon!,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Icon(widget.fallbackIcon,
                            color: widget.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.25,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 12.5,
                            height: 1.3,
                            color: subColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.badgeCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.splashGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${widget.badgeCount}',
                        style: const TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.splashGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  RotationTransition(
                    turns: Tween<double>(begin: 0, end: 0.5).animate(_curve),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: chevronColor,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _curve,
            child: FadeTransition(
              opacity: _curve,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(height: 1, thickness: 1, color: divider),
                  for (var i = 0; i < widget.rows.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 56),
                        child: Divider(height: 1, thickness: 1, color: divider),
                      ),
                    widget.rows[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Akkordeon ichidagi bitta xizmat qatori.
class ServiceGroupRow extends StatelessWidget {
  const ServiceGroupRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.trailing,
    this.assetIcon,
    this.iconScale = 1.0,
    this.fallbackIcon = Icons.description_outlined,
    this.selected = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget trailing;

  /// Xizmatning o'z 3D ikonkasi (ro'yxatdagi kartalar bilan bir xil asset).
  /// Null bo'lsa [fallbackIcon] glifi chiziladi.
  final String? assetIcon;
  final double iconScale;
  final IconData fallbackIcon;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final badgeBg = selected
        ? AppColors.splashGreen.withValues(alpha: 0.16)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1F2F4));
    final badgeFg = selected
        ? AppColors.splashGreen
        : (isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF6B7278));

    return InkWell(
      onTap: hapticTap(onTap),
      child: Container(
        color: selected
            ? AppColors.splashGreen.withValues(alpha: isDark ? 0.10 : 0.07)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              padding: assetIcon != null
                  ? const EdgeInsets.all(3)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: assetIcon != null
                  ? Transform.scale(
                      scale: iconScale,
                      child: Image.asset(assetIcon!, fit: BoxFit.contain),
                    )
                  : Icon(fallbackIcon, size: 17, color: badgeFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.25,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 12,
                      height: 1.3,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
