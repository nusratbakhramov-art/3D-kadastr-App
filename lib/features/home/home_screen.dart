import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../core/haptics.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../support/support_service.dart';
import '../market/market_controller.dart';
import '../market/models/market_listing.dart';
import '../market/listing_detail_screen.dart';
import '../market/widgets/featured_carousel.dart';
import '../chat/screens/chat_screen.dart';
import '../onboarding/onboarding_page_data.dart';
import '../services/models/service_item.dart';
import '../services/widgets/service_card.dart';
import 'user_profile.dart';
import 'widgets/home_header.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.locale = AppLocale.uz,
    this.today,
    this.onLoginTap,
    this.onOpenKadastr3d,
    this.onOpenAiValuation,
    this.onOpenMarket,
    this.onOpenKalkulyator,
    this.onOpenOrder,
    this.onOpenProfile,
    this.onOpenNotifications,
  });

  final Locale locale;
  final DateTime? today;
  final VoidCallback? onLoginTap;
  final VoidCallback? onOpenKadastr3d;
  final VoidCallback? onOpenAiValuation;
  final VoidCallback? onOpenMarket;
  final VoidCallback? onOpenKalkulyator;
  final VoidCallback? onOpenOrder;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenNotifications;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MarketController _marketController;
  final ScrollController _scroll = ScrollController();
  final SupportService _supportService = SupportService();

  // The FABs auto-hide while the user scrolls down (reading through the feed)
  // and come back on any upward move, when the scroll settles, or at the top.
  //
  // A notifier, NOT setState: the visibility flips repeatedly mid-fling (drag →
  // idle → drag), and a setState here rebuilt the whole feed — header, three
  // service cards, the carousel — on every flip, right when the raster thread
  // was already busy scrolling. Only the two FABs listen now.
  final ValueNotifier<bool> _fabsVisible = ValueNotifier<bool>(true);
  SupportInfo _supportInfo = const SupportInfo(
    phone: SupportService.fallbackPhone,
  );

  @override
  void initState() {
    super.initState();
    _marketController = sharedMarketController(
      locale: widget.locale.languageCode,
    );
    unawaited(_marketController.initialize());
    unawaited(_loadSupportInfo());
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _fabsVisible.dispose();
    super.dispose();
  }

  // The Call markaz block owns the very bottom of the feed, so the FABs step
  // aside for that short stretch (not the whole tail) to avoid sitting on it.
  static const double _bottomHideZone = 130;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final nearBottom = pos.pixels >= pos.maxScrollExtent - _bottomHideZone;
    // Reverse == dragging content up (reading downward) → hide. Otherwise show,
    // except across the bottom stretch where the call block takes over. The
    // pixels<=0 guard stops a top overscroll bounce from sticking them hidden.
    final show = pos.pixels <= 0 ||
        (!nearBottom && pos.userScrollDirection != ScrollDirection.reverse);
    // ValueNotifier already no-ops when the value is unchanged.
    _fabsVisible.value = show;
  }

  Future<void> _loadSupportInfo() async {
    final info = await _supportService.fetchInfo();
    if (mounted) setState(() => _supportInfo = info);
  }

  Future<void> _callSupport() async {
    final uri = Uri(scheme: 'tel', path: _supportInfo.phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // tel: ochilmasa jimgina o'tamiz.
    }
  }

  void _onListingTap(MarketListing listing) {
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    Navigator.of(context).push(
      isIos
          ? PageRouteBuilder<void>(
              pageBuilder: (_, __, ___) =>
                  ListingDetailScreen(listing: listing),
              transitionsBuilder: (_, animation, __, child) {
                return SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                );
              },
            )
          : PageRouteBuilder<void>(
              transitionDuration: const Duration(milliseconds: 360),
              reverseTransitionDuration: const Duration(milliseconds: 280),
              pageBuilder: (_, __, ___) =>
                  ListingDetailScreen(listing: listing),
              transitionsBuilder: (_, animation, __, child) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.today ?? DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppColors.greenBlack
        : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: backgroundColor,
      // Pastki-o'ng: qo'ng'iroq — kiruvchi qo'ng'iroqdagi "javob berish" kabi
      // yashil (chap tomondagi qizil chat bilan juftlikda).
      floatingActionButton: _FabReveal(
        visible: _fabsVisible,
        child: _ImageFab(
          asset: 'assets/icons/ai-phone-icon.png',
          onTap: hapticTap(_callSupport),
          tooltip: tr(widget.locale, 'home.fab.call'),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _HomePatternBackground(
            backgroundColor: backgroundColor,
            showPattern: !isDark,
          ),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              controller: _scroll,
              clipBehavior: Clip.none,
              // Modest tail — the FABs step aside across the bottom stretch, so
              // the block doesn't need a big gap to clear them.
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              // Every block below is wrapped in a RepaintBoundary. A
              // SingleChildScrollView — unlike a sliver list — adds none of its
              // own, so without them one scroll frame re-rasterised the whole
              // column: three cards' radial glow + elevation shadow + six
              // strings each carrying three blurred text shadows, the carousel,
              // and the pattern. With them, scrolling just translates layers
              // the raster cache already holds.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RepaintBoundary(
                    child: ValueListenableBuilder<UserProfile?>(
                      valueListenable: userProfileNotifier,
                      builder: (context, profile, _) {
                        return ValueListenableBuilder<int>(
                          valueListenable: notificationUnreadNotifier,
                          builder: (context, unread, _) {
                            return HomeHeader(
                              profile: profile,
                              unreadCount: unread,
                              locale: widget.locale,
                              today: date,
                              onLoginTap: widget.onLoginTap,
                              onAvatarTap: widget.onOpenProfile,
                              onBellTap: widget.onOpenNotifications,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  RepaintBoundary(
                    child: _CardsGrid(
                      locale: widget.locale,
                      onOpenKadastr3d: widget.onOpenKadastr3d,
                      onOpenAiValuation: widget.onOpenAiValuation,
                      onOpenKalkulyator: widget.onOpenKalkulyator,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: _sectionTitle(widget.locale),
                    locale: widget.locale,
                    onSeeAll: widget.onOpenMarket,
                  ),
                  const SizedBox(height: 12),
                  RepaintBoundary(
                    child: FeaturedCarousel(
                      controller: _marketController,
                      onTap: _onListingTap,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Support number — always in the feed. Rendering it only at
                  // the bottom made the scroll extent jump as it popped in/out
                  // (it grew the list, which flipped the at-bottom check off,
                  // which removed it — an oscillation that read as a glitch).
                  // The floating FABs step aside via _atBottom instead, so they
                  // don't cover it down here.
                  RepaintBoundary(
                    child: _CallCenterBlock(
                      phone: _supportInfo.phone,
                      locale: widget.locale,
                      onTap: hapticTap(_callSupport),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Pastki-chap: chat — kiruvchi qo'ng'iroqdagi "rad etish" kabi qizil.
          Positioned(
            left: 16,
            bottom: 16,
            child: _FabReveal(
              visible: _fabsVisible,
              child: _ImageFab(
                asset: 'assets/icons/ai-chat-icon.png',
                onTap: hapticTap(
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(locale: widget.locale),
                    ),
                  ),
                ),
                tooltip: tr(widget.locale, 'home.fab.assistant'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Keyed so the panel can reword it; "home.see_all" beside it already is.
  static String _sectionTitle(Locale l) => tr(l, 'home.section.top_models');
}

/// A floating action button whose whole face is a supplied PNG (the icon
/// already carries its own colour/disc), with a soft drop shadow so it lifts
/// off the content and a tap target matched to the 64pt gradient FABs it sits
/// beside.
///
/// The shadow used to be a blurred silhouette of the PNG itself
/// (`ImageFiltered` + `ImageFilter.blur`). That is a live GPU blur of a
/// saveLayer, re-run on every frame the FAB paints — and because it sits inside
/// the reveal's `AnimatedScale`, the raster cache could never hold it. Two of
/// them, over a scrolling feed, was the single most expensive thing on Home.
/// Both icons are full-bleed circular discs (their alpha is a circle inscribed
/// in the 400×400 box), so an ordinary circular `BoxShadow` draws the same
/// shape for free.
class _ImageFab extends StatelessWidget {
  const _ImageFab({
    required this.asset,
    required this.onTap,
    required this.tooltip,
  });

  final String asset;
  final VoidCallback? onTap;
  final String tooltip;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    // The PNGs are 400×400 — decoding them at that size to draw at 56pt burns
    // ~640 KB and a downscale per paint. Decode straight to the device size.
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Image.asset(
            asset,
            width: _size,
            height: _size,
            fit: BoxFit.contain,
            cacheWidth: (_size * dpr).round(),
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

/// Scales + fades a FAB away while the feed scrolls under it.
///
/// Subscribes to the visibility itself so a scroll never rebuilds anything
/// above it, and sits behind a [RepaintBoundary] so the reveal animation
/// repaints 56pt of FAB rather than the whole Home stack under it.
class _FabReveal extends StatelessWidget {
  const _FabReveal({required this.visible, required this.child});

  final ValueListenable<bool> visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: visible,
        child: child,
        builder: (context, show, child) {
          return AnimatedScale(
            scale: show ? 1 : 0,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 170),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.locale,
    this.subtitle,
    this.onSeeAll,
  });
  final String title;
  final String? subtitle;
  final Locale locale;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subtitleColor = isDark ? Colors.white70 : AppColors.textBlack.withValues(alpha: 0.55);
    final linkColor = AppColors.splashGreen;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: subtitleColor,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: hapticTap(onSeeAll),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _HomeScreenStrings.seeAll(locale),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: linkColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HomePatternBackground extends StatelessWidget {
  const _HomePatternBackground({
    required this.backgroundColor,
    required this.showPattern,
  });

  final Color backgroundColor;
  final bool showPattern;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The source is 1468×1516 — ~8.9 MB of decoded ARGB for something
            // drawn one screen wide. Decode it at the width it's actually
            // painted at instead.
            final dpr = MediaQuery.of(context).devicePixelRatio;
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: backgroundColor),
                  ),
                ),
                if (showPattern)
                  Positioned(
                    top: 0,
                    right: 0,
                    width: constraints.maxWidth,
                    height: constraints.maxWidth,
                    child: Image.asset(
                      'assets/images/home/pattern.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.topRight,
                      cacheWidth: (constraints.maxWidth * dpr).round(),
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The Home service grid — the rich dark cards brought over from the (removed)
/// Services page: two square cards (AI Baholash, 3D Kadastr) + one wide card
/// (Kalkulyator), each with an accent glow and a 3D image. Market lives in the
/// bottom tab + "Top modellar", so it's not a card here.
class _CardsGrid extends StatelessWidget {
  const _CardsGrid({
    required this.locale,
    this.onOpenKadastr3d,
    this.onOpenAiValuation,
    this.onOpenKalkulyator,
  });

  final Locale locale;
  final VoidCallback? onOpenKadastr3d;
  final VoidCallback? onOpenAiValuation;
  final VoidCallback? onOpenKalkulyator;

  @override
  Widget build(BuildContext context) {
    final l = locale;
    final kadastr = ServiceItem(
      id: ServiceId.kadastr3d,
      title: _CardStrings.kadastr3d(l),
      subtitle: _CardStrings.kadastr3dSub(l),
      asset: 'assets/images/home/cta-icon.png',
      accent: const Color(0xFF00E135),
      layout: ServiceLayout.square,
    );
    final ai = ServiceItem(
      id: ServiceId.aiValuation,
      title: _CardStrings.aiValuation(l),
      subtitle: _CardStrings.aiValuationSub(l),
      asset: 'assets/images/services/ai.png',
      accent: const Color(0xFF7C3AED),
      layout: ServiceLayout.square,
    );
    final calculator = ServiceItem(
      id: ServiceId.calculator,
      title: _CardStrings.calculator(l),
      subtitle: _CardStrings.calculatorSub(l),
      asset: 'assets/images/services/calculator.png',
      accent: const Color(0xFF22D3EE),
      layout: ServiceLayout.wide,
    );

    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final squareWidth = (constraints.maxWidth - gap) / 2;
        const squareAspect = 0.78;
        // The cards are sized by aspect ratio, so on a Pro Max-class phone the
        // extra width used to stretch them ~30pt taller than the artwork and
        // copy need — a dead gap under the subtitle, and "Top modellar" pushed
        // off-screen. Cap the height so surplus width widens the cards instead
        // of stretching them; narrow phones keep the original proportions.
        // The floor is deliberately tall: the 3D logo is bottom-anchored, so a
        // taller card pushes it down and away from the top-left copy, which is
        // what keeps the subtitle off the logo on small phones (e.g. S23).
        final squareHeight = (squareWidth / squareAspect).clamp(172.0, 230.0);
        // Keep the wide (Calculator) card at its ORIGINAL height — it must not
        // grow just because the square cards got taller, so it's derived from
        // the old square proportion, not the new taller one.
        final wideHeight = (squareWidth / 0.84).clamp(150.0, 208.0) * 0.72;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: squareHeight,
              child: Row(
                children: [
                  Expanded(
                    child: ServiceCard(
                      item: ai,
                      onTap: onOpenAiValuation ?? () {},
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: ServiceCard(
                      item: kadastr,
                      onTap: onOpenKadastr3d ?? () {},
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: gap),
            SizedBox(
              height: wideHeight,
              width: double.infinity,
              child: ServiceCard(
                item: calculator,
                onTap: onOpenKalkulyator ?? () {},
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CardStrings {
  const _CardStrings._();

  static String kadastr3d(Locale l) => tr(l, 'home.card.kadastr3d');

  static String kadastr3dSub(Locale l) => tr(l, 'home.card.kadastr3d_sub');

  static String aiValuation(Locale l) => tr(l, 'home.card.ai_valuation');

  static String aiValuationSub(Locale l) => tr(l, 'home.card.ai_valuation_sub');

  static String calculator(Locale l) => tr(l, 'home.card.calculator');

  static String calculatorSub(Locale l) => tr(l, 'home.card.calculator_sub');
}

class _HomeScreenStrings {
  const _HomeScreenStrings._();

  static String seeAll(Locale l) => tr(l, 'home.see_all');
}

/// Bottom-of-feed "Call center" block. Revealed only when scrolled to the very
/// bottom, reusing the same phone glyph as the bottom-right call FAB.
class _CallCenterBlock extends StatelessWidget {
  const _CallCenterBlock({
    required this.phone,
    required this.locale,
    required this.onTap,
  });

  final String phone;
  final Locale locale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        // No card bg/border — the green orb + phone number / 24/7 sit centred
        // directly on the feed background. The number (fetched from backend) is
        // the hero line; the hours read as a quiet subline beneath it.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icons/ai-phone-icon.png',
              width: 46,
              height: 46,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phone,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    letterSpacing: 0.2,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  tr(locale, 'home.contact_center.hours'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                    color: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
