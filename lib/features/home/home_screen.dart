import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import '../support/support_service.dart';
import '../market/market_controller.dart';
import '../market/models/market_listing.dart';
import '../market/listing_detail_screen.dart';
import '../market/widgets/featured_carousel.dart';
import '../chat/screens/chat_screen.dart';
import '../onboarding/onboarding_page_data.dart';
import 'user_profile.dart';
import 'widgets/home_card.dart';
import 'widgets/home_cta.dart';
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
  final SupportService _supportService = SupportService();
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'homeChatFab',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatScreen(locale: widget.locale),
          ),
        ),
        backgroundColor: AppColors.splashGreen,
        foregroundColor: AppColors.greenBlack,
        tooltip: 'Yordamchi',
        child: const Icon(Icons.chat_bubble_rounded),
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
              clipBehavior: Clip.none,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<UserProfile?>(
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
                  const SizedBox(height: 20),
                  _CardsGrid(
                    locale: widget.locale,
                    onOpenKadastr3d: widget.onOpenKadastr3d,
                    onOpenAiValuation: widget.onOpenAiValuation,
                    onOpenMarket: widget.onOpenMarket,
                    onOpenKalkulyator: widget.onOpenKalkulyator,
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<UserProfile?>(
                    valueListenable: userProfileNotifier,
                    builder: (context, profile, _) {
                      return HomeCta(
                        isGuest: profile == null,
                        locale: widget.locale,
                        onLoginTap: widget.onLoginTap,
                        onOrderTap: widget.onOpenOrder,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: _sectionTitle(widget.locale),
                    locale: widget.locale,
                    onSeeAll: widget.onOpenMarket,
                  ),
                  const SizedBox(height: 12),
                  FeaturedCarousel(
                    controller: _marketController,
                    onTap: _onListingTap,
                  ),
                ],
              ),
            ),
          ),
          // Pastki-chap: qo'ng'iroq tugmasi (chat tugmasi bilan bir xil uslub).
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'homeCallFab',
              onPressed: _callSupport,
              backgroundColor: AppColors.splashGreen,
              foregroundColor: AppColors.greenBlack,
              tooltip: 'Qo\'ng\'iroq',
              child: const Icon(Icons.call_rounded),
            ),
          ),
        ],
      ),
    );
  }

  static String _sectionTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Топ модели',
    'en' => 'Top models',
    _ => 'Top modellar',
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.locale,
    this.onSeeAll,
  });
  final String title;
  final Locale locale;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final linkColor = AppColors.splashGreen;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              _HomeScreenStrings.seeAll(locale),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: linkColor,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
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
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CardsGrid extends StatelessWidget {
  const _CardsGrid({
    required this.locale,
    this.onOpenKadastr3d,
    this.onOpenAiValuation,
    this.onOpenMarket,
    this.onOpenKalkulyator,
  });

  final Locale locale;
  final VoidCallback? onOpenKadastr3d;
  final VoidCallback? onOpenAiValuation;
  final VoidCallback? onOpenMarket;
  final VoidCallback? onOpenKalkulyator;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    const height = 97.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: HomeCard(
                  title: _CardStrings.kadastr3d(locale),
                  iconAsset: 'assets/images/home/card-3d.svg',
                  onTap: onOpenKadastr3d,
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: HomeCard(
                  title: _CardStrings.aiValuation(locale),
                  iconAsset: 'assets/images/home/card-ai.svg',
                  onTap: onOpenAiValuation,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: gap),
        SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: HomeCard(
                  title: _CardStrings.calculator(locale),
                  iconAsset: 'assets/images/home/card-calculator.svg',
                  onTap: onOpenKalkulyator,
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: HomeCard(
                  title: _CardStrings.market(locale),
                  iconAsset: 'assets/images/home/card-market.svg',
                  onTap: onOpenMarket,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardStrings {
  const _CardStrings._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) {
        'ru' => ru,
        'en' => en,
        _ => uz,
      };

  static String kadastr3d(Locale l) =>
      _pick(l, '3D kadastr', '3D кадастр', '3D cadastre');

  static String aiValuation(Locale l) =>
      _pick(l, 'AI baholash', 'AI оценка', 'AI valuation');

  static String market(Locale l) => _pick(l, 'Market', 'Маркет', 'Market');

  static String calculator(Locale l) =>
      _pick(l, 'Kalkulyator', 'Калькулятор', 'Calculator');
}

class _HomeScreenStrings {
  const _HomeScreenStrings._();

  static String seeAll(Locale l) => switch (l.languageCode) {
    'ru' => 'Все →',
    'en' => 'See all →',
    _ => 'Barchasi →',
  };
}
