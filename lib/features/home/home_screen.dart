import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
      // Pastki-o'ng: qo'ng'iroq — kiruvchi qo'ng'iroqdagi "javob berish" kabi
      // yashil (chap tomondagi qizil chat bilan juftlikda).
      floatingActionButton: FloatingActionButton(
        heroTag: 'homeCallFab',
        onPressed: hapticTap(_callSupport),
        backgroundColor: AppColors.splashGreen,
        foregroundColor: AppColors.greenBlack,
        tooltip: switch (widget.locale.languageCode) {
          'ru' => 'Позвонить',
          'en' => 'Call',
          _ => 'Qo\'ng\'iroq',
        },
        child: const Icon(Icons.call_rounded),
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
                    onOpenKalkulyator: widget.onOpenKalkulyator,
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
          // Pastki-chap: chat — kiruvchi qo'ng'iroqdagi "rad etish" kabi qizil.
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'homeChatFab',
              onPressed: hapticTap(
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatScreen(locale: widget.locale),
                  ),
                ),
              ),
              backgroundColor: AppColors.declineRed,
              foregroundColor: Colors.white,
              tooltip: switch (widget.locale.languageCode) {
                'ru' => 'Помощник',
                'en' => 'Assistant',
                _ => 'Yordamchi',
              },
              // Agent/bot mark — stroke-based, so it needs an explicit tint:
              // SvgPicture doesn't inherit the FAB's foregroundColor. Sized a
              // touch over the 24pt icon grid because a stroked glyph reads
              // lighter than the solid phone it's paired with.
              child: SvgPicture.asset(
                'assets/icons/chat-bot.svg',
                width: 26,
                height: 26,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
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
            onTap: hapticTap(onSeeAll),
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
        const squareAspect = 0.84;
        // The cards are sized by aspect ratio, so on a Pro Max-class phone the
        // extra width used to stretch them ~30pt taller than the artwork and
        // copy need — a dead gap under the subtitle, and "Top modellar" pushed
        // off-screen. Cap the height so surplus width widens the cards instead
        // of stretching them; narrow phones keep the original proportions.
        final squareHeight = (squareWidth / squareAspect).clamp(150.0, 208.0);
        final wideHeight = (squareHeight * 0.88).clamp(160.0, 240.0);

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

  static String _pick(Locale l, String key, String uz, String ru, String en) =>
      tr(l, key, uz: uz, ru: ru, en: en);

  static String kadastr3d(Locale l) => _pick(
    l,
    'home.card.kadastr3d',
    '3D kadastr',
    '3D кадастр',
    '3D cadastre',
  );

  static String kadastr3dSub(Locale l) => _pick(
    l,
    'home.card.kadastr3d_sub',
    'Xizmatlar narxini hisoblang va ariza qoldiring.',
    'Рассчитайте стоимость услуг и оставьте заявку.',
    'Calculate service prices and submit an application.',
  );

  static String aiValuation(Locale l) => _pick(
    l,
    'home.card.ai_valuation',
    'AI baholash',
    'AI оценка',
    'AI valuation',
  );

  static String aiValuationSub(Locale l) => _pick(
    l,
    'home.card.ai_valuation_sub',
    'Sun\'iy intellekt yordamida ko\'chmas mulk qiymatini aniqlash.',
    'Оценка стоимости недвижимости с помощью ИИ.',
    'Real estate valuation powered by AI.',
  );

  static String calculator(Locale l) => _pick(
    l,
    'home.card.calculator',
    'Kalkulyator',
    'Калькулятор',
    'Calculator',
  );

  static String calculatorSub(Locale l) => _pick(
    l,
    'home.card.calculator_sub',
    'Arxitektura, dizayn, qurilish narxlarini hisoblash.',
    'Расчёт стоимости архитектуры, дизайна и строительства.',
    'Calculate architecture, design and construction costs.',
  );
}

class _HomeScreenStrings {
  const _HomeScreenStrings._();

  static String seeAll(Locale l) =>
      tr(l, 'home.see_all', uz: 'Barchasi →', ru: 'Все →', en: 'See all →');
}
