import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../auth/widgets/login_required_sheet.dart';
import 'models/service_item.dart';
import 'screens/ai_scan_intro_screen.dart';
import 'screens/kadastr_3d_screen.dart';
import 'screens/online_calculator_screen.dart';
import 'screens/smeta/smeta_editor_screen.dart';
import 'widgets/service_card.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({
    super.key,
    this.locale = const Locale('uz'),
    this.animateToken = 0,
  });

  final Locale locale;

  /// Bumped by parent to retrigger the entry animation (e.g. when the
  /// Services tab becomes active again).
  final int animateToken;

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(ServicesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateToken != oldWidget.animateToken) {
      _controller
        ..reset()
        ..forward();
    }
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
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final locale = widget.locale;

    final items = <ServiceItem>[
      ServiceItem(
        id: ServiceId.kadastr3d,
        title: ServiceStrings.kadastrTitle(locale),
        subtitle: ServiceStrings.kadastrSubtitle(locale),
        asset: 'assets/images/home/cta-icon.png',
        accent: const Color(0xFF00E135),
        layout: ServiceLayout.square,
      ),
      ServiceItem(
        id: ServiceId.aiValuation,
        title: ServiceStrings.aiTitle(locale),
        subtitle: ServiceStrings.aiSubtitle(locale),
        asset: 'assets/images/services/ai.png',
        accent: const Color(0xFF7C3AED),
        layout: ServiceLayout.square,
      ),
      ServiceItem(
        id: ServiceId.calculator,
        title: ServiceStrings.calculatorTitle(locale),
        subtitle: ServiceStrings.calculatorSubtitle(locale),
        asset: 'assets/images/services/calculator.png',
        accent: const Color(0xFF22D3EE),
        layout: ServiceLayout.wide,
      ),
      ServiceItem(
        id: ServiceId.smetaPro,
        title: ServiceStrings.smetaProTitle(locale),
        subtitle: ServiceStrings.smetaProSubtitle(locale),
        asset: 'assets/images/services/calculator.png',
        accent: const Color(0xFFF59E0B),
        layout: ServiceLayout.wide,
      ),
    ];

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalPadding = 16.0;
            const gap = 12.0;
            final maxWidth = constraints.maxWidth;
            final cardMaxRowWidth = (maxWidth - horizontalPadding * 2).clamp(
              0.0,
              720.0,
            );
            final squareCardWidth = (cardMaxRowWidth - gap) / 2;
            const squareAspect = 0.84;
            final squareHeight = squareCardWidth / squareAspect;
            final wideHeight = (squareHeight * 0.78).clamp(150.0, 220.0);

            return ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12,
                horizontalPadding,
                32,
              ),
              children: [
                _StaggeredEntry(
                  controller: _controller,
                  index: 0,
                  child: Text(
                    ServiceStrings.pageTitle(locale),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      height: 1.15,
                      color: titleColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardMaxRowWidth),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _StaggeredEntry(
                                controller: _controller,
                                index: 1,
                                child: SizedBox(
                                  height: squareHeight,
                                  child: ServiceCard(
                                    item: items[0],
                                    onTap: () => _open(context, items[0]),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: gap),
                            Expanded(
                              child: _StaggeredEntry(
                                controller: _controller,
                                index: 2,
                                child: SizedBox(
                                  height: squareHeight,
                                  child: ServiceCard(
                                    item: items[1],
                                    onTap: () => _open(context, items[1]),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: gap),
                        _StaggeredEntry(
                          controller: _controller,
                          index: 3,
                          child: SizedBox(
                            height: wideHeight,
                            width: double.infinity,
                            child: ServiceCard(
                              item: items[2],
                              onTap: () => _open(context, items[2]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, ServiceItem item) async {
    switch (item.id) {
      case ServiceId.kadastr3d:
        // 3D Kadastr needs an account (davreest.uz lookup + job submit) — gate
        // the entry with a login drawer before the wizard opens.
        if (!await ensureLoggedIn(context)) {
          return;
        }
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const Kadastr3dScreen()),
        );
      case ServiceId.aiValuation:
        // AI Baholash needs an account (davreest.uz lookup + job submit).
        // Gate the entry with a login drawer before the wizard opens.
        if (!await ensureLoggedIn(context)) {
          return;
        }
        if (!context.mounted) return;
        // Start at the 3D-scan intro (step 1) — same entry as the Home tile.
        // (Pushing AiCadastreScreen here skipped the scan step.)
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AiScanIntroScreen(),
          ),
        );
      case ServiceId.calculator:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const OnlineCalculatorScreen(),
          ),
        );
      case ServiceId.smetaPro:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SmetaEditorScreen()),
        );
    }
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
    const startStep = 0.12;
    final start = (index * startStep).clamp(0.0, 0.6);
    final end = (start + 0.55).clamp(0.0, 1.0);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(curved);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: offset, child: child),
    );
  }
}
