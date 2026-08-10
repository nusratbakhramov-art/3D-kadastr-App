import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../models/calculator_draft.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/service_group_card.dart';
import 'calculator/arxitektura_form_screen.dart';
import 'calculator/baholash_form_screen.dart';
import 'calculator/buxgalteriya_screen.dart';
import 'calculator/dizayn_form_screen.dart';
import 'calculator/kadastr_form_screen.dart';
import 'calculator/tamirlash_form_screen.dart';
import 'calculator/yuridik_screen.dart';

class OnlineCalculatorScreen extends StatefulWidget {
  const OnlineCalculatorScreen({super.key});

  @override
  State<OnlineCalculatorScreen> createState() => _OnlineCalculatorScreenState();
}

class _OnlineCalculatorScreenState extends State<OnlineCalculatorScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final locale = Localizations.localeOf(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContent = constraints.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      // Bu ro'yxat bosh sahifadagi "3D kadastr" kartadan
                      // ochiladi — sarlavha karta bilan bir xil bo'lishi kerak.
                      // (`services.calc.appbar` prod'da "Onlayn kalkulyator"ga
                      // qotirilgan, shuning uchun alohida kalit.)
                      child: ServiceAppBar(
                        title: tr(locale, 'services.calc.appbar.k3d'),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          _StaggeredEntry(
                            controller: _controller,
                            index: 0,
                            child: Text(
                              tr(locale, 'services.calc.choose_service_heading'),
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w900,
                                fontSize: 24,
                                height: 1.2,
                                color: headingColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _StaggeredEntry(
                            controller: _controller,
                            index: 0,
                            child: Text(
                              tr(locale, 'services.calc.subheading'),
                              style: TextStyle(
                                fontFamily: 'MTSText',
                                fontSize: 13,
                                height: 1.4,
                                color: subColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          for (var i = 0;
                              i < CalculatorCategory.listedGroups.length;
                              i++) ...[
                            _StaggeredEntry(
                              controller: _controller,
                              index: i + 1,
                              child: _groupCard(
                                context,
                                CalculatorCategory.listedGroups[i],
                                locale,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Bitta xizmat — oddiy karta; bir nechtasi — akkordeon (kadastr guruhi).
  Widget _groupCard(
    BuildContext context,
    List<CalculatorCategory> group,
    Locale locale,
  ) {
    if (group.length == 1) {
      return _CategoryCard(
        category: group.first,
        locale: locale,
        onTap: () => _open(context, group.first),
      );
    }
    final head = group.first;
    final chevronColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.4)
        : const Color(0xFFB4B9BF);
    return ServiceGroupCard(
      title: kadastrGroupTitle(locale),
      subtitle: kadastrGroupSubtitle(locale),
      assetIcon: head.assetIcon,
      iconScale: head.iconScale,
      fallbackIcon: head.icon,
      accent: head.accent,
      rows: [
        for (final c in group)
          ServiceGroupRow(
            title: c.rowTitle(locale),
            subtitle: c.rowSubtitle(locale),
            assetIcon: c.rowAssetIcon,
            iconScale: c.iconScale,
            fallbackIcon: c.icon,
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: chevronColor,
              size: 20,
            ),
            onTap: () => _open(context, c),
          ),
      ],
    );
  }

  void _open(BuildContext context, CalculatorCategory cat) {
    final WidgetBuilder builder = switch (cat) {
      CalculatorCategory.arxitektura => (_) => const ArxitekturaFormScreen(),
      CalculatorCategory.kadastr => (_) =>
          const KadastrFormScreen(is3d: false),
      CalculatorCategory.kadastr3d => (_) =>
          const KadastrFormScreen(is3d: true),
      CalculatorCategory.baholash => (_) => const BaholashFormScreen(),
      CalculatorCategory.dizayn => (_) => const DizaynFormScreen(),
      CalculatorCategory.tamirlash => (_) => const TamirlashFormScreen(),
      CalculatorCategory.buxgalteriya => (_) => const BuxgalteriyaScreen(),
      CalculatorCategory.yuridik => (_) => const YuridikScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.locale,
    required this.onTap,
  });

  final CalculatorCategory category;
  final Locale locale;
  final VoidCallback onTap;

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

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: category.assetIcon != null
                    ? const EdgeInsets.all(4)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  // Whiteish neutral tile so the colourful 3D icons pop.
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF1F2F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: category.assetIcon != null
                    ? Transform.scale(
                        scale: category.iconScale,
                        child: Image.asset(
                          category.assetIcon!,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Icon(category.icon, color: category.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title(locale),
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
                      category.subtitle(locale),
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
              Icon(
                Icons.chevron_right_rounded,
                color: chevronColor,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaggeredEntry extends StatelessWidget {
  const _StaggeredEntry({
    required this.controller,
    required this.index,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const startStep = 0.07;
    final start = (index * startStep).clamp(0.0, 0.6);
    final end = (start + 0.5).clamp(0.0, 1.0);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.16),
      end: Offset.zero,
    ).animate(curved);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: offset, child: child),
    );
  }
}
