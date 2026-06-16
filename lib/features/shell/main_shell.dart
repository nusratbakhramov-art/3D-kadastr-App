import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_navigation.dart';
import '../../core/push_notifications.dart';
import '../auth/auth_flow_screen.dart';
import '../auth/auth_storage.dart';
import '../auth/widgets/login_required_sheet.dart';
import '../applications/applications_screen.dart';
import '../help/help_screen.dart';
import '../home/home_screen.dart';
import '../home/user_profile.dart';
import '../market/market_screen.dart';
import '../notifications/notifications_screen.dart';
import '../onboarding/onboarding_page_data.dart';
import '../payments/payments_screen.dart';
import '../profile/my_profile_screen.dart';
import '../profile/profile_screen.dart';
import '../ratings/my_ratings_screen.dart';
import '../scans/saved_scans_screen.dart';
import '../services/screens/ai_drafts_screen.dart';
// TEMP (simulator testing): AI Baholash 3D-skan introsi o'tkazib yuborilgan.
// Reliz oldidan qaytarish: import '../services/screens/ai_scan_intro_screen.dart';
import '../services/screens/ai_cadastre_screen.dart';
import '../services/screens/kadastr_3d_screen.dart';
import '../services/screens/online_calculator_screen.dart';
import '../services/services_screen.dart';
import '../settings/settings_screen.dart';
import 'app_bottom_nav.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.locale = AppLocale.uz,
    this.authStorage = const AuthStorage(),
  });

  final Locale locale;
  final AuthStorage authStorage;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _servicesAnimToken = 0;
  int _profileAnimToken = 0;
  int _applicationsAnimToken = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    // Push / deep-link orqali tab almashtirish signalini tinglaymiz.
    shellTabRequest.addListener(_onShellTabRequest);
    // Cold start: app push bosilib ochilгan bo'lsa, kutilayotgan tab bor.
    if (shellTabRequest.value >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onShellTabRequest());
    }
  }

  void _onShellTabRequest() {
    final i = shellTabRequest.value;
    if (i < 0 || !mounted) return;
    shellTabRequest.value = -1; // bir martalik — reset
    _onTabChanged(i);
  }

  @override
  void dispose() {
    shellTabRequest.removeListener(_onShellTabRequest);
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int i) {
    if (i == _index) return;
    final delta = (i - _index).abs();
    setState(() {
      _index = i;
      if (i == 1) _servicesAnimToken++;
      if (i == 3) _applicationsAnimToken++;
      if (i == 4) _profileAnimToken++;
    });
    if (delta > 1) {
      _pageController.jumpToPage(i);
    } else {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _openAuth() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (_, _, _) => AuthFlowScreen(
          storage: widget.authStorage,
          onAuthenticated: () => Navigator.of(context).pop(),
          onSkip: () => Navigator.of(context).pop(),
        ),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (mounted) setState(() {});
    // Login bo'lган bo'lsa — FCM tokenni backendga bog'laymiz.
    unawaited(PushNotifications.syncToken());
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          onLogoutConfirmed: _handleLogout,
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    // Tokenni backenddan o'chiramiz (storage tozalanishidan oldin — auth kerak).
    final session = await widget.authStorage.loadSession();
    final token = session.token;
    if (token != null) {
      await PushNotifications.unregister(token);
    }
    await widget.authStorage.clear();
    userProfileNotifier.value = null;
    notificationUnreadNotifier.value = 0;
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _index = 0);
    _pageController.jumpToPage(0);
  }

  Future<void> _openMyProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MyProfileScreen()));
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  Future<void> _openHelp() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));
  }

  Future<void> _openRatings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MyRatingsScreen()));
  }

  Future<void> _openScans() async {
    // Real oqim: lokal "Mening skanlarim" o'rniga backend draftlar
    // ("Mening arizalarim"). Skanlar endi ariza ichida backendda saqlanadi.
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AiDraftsScreen()));
  }

  Future<void> _openSavedScans() async {
    // Lokal "Mening skanlarim" — saqlangan raw skanlar + qayta ishlash (outputs
    // history) bilan natijani yaxshilash/test qilish uchun.
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SavedScansScreen()));
  }

  Future<void> _openPayments() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PaymentsScreen()));
  }

  Future<void> _openKadastr3d() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const Kadastr3dScreen()));
  }

  Future<void> _openAiValuation() async {
    // AI Baholash needs an account — gate with a login drawer before the
    // wizard opens (kadastr → client → location → purpose → intake → result).
    if (!await ensureLoggedIn(
      context,
      storage: widget.authStorage,
    )) {
      return;
    }
    if (!mounted) return;
    // TEMP (simulator testing): 3D-skan introsini o'tkazib yuboramiz. Reliz
    // oldidan qaytarish: builder: (_) => const AiScanIntroScreen().
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'ai/cadastre'),
      builder: (_) => const AiCadastreScreen(),
    ));
  }

  void _openCalculator() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OnlineCalculatorScreen()),
    );
  }

  void _openMarketTab() => _onTabChanged(2);

  @override
  Widget build(BuildContext context) {
    final items = _ShellStrings.items(widget.locale);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) {
          if (i != _index) setState(() => _index = i);
        },
        children: [
          HomeScreen(
            locale: widget.locale,
            onLoginTap: _openAuth,
            onOpenKadastr3d: _openKadastr3d,
            onOpenAiValuation: _openAiValuation,
            onOpenCalculator: _openCalculator,
            onOpenMarket: _openMarketTab,
            onOpenOrder: _openKadastr3d,
            onOpenProfile: () => _onTabChanged(4),
            onOpenNotifications: _openNotifications,
          ),
          ServicesScreen(
            locale: widget.locale,
            animateToken: _servicesAnimToken,
          ),
          const MarketScreen(),
          ApplicationsScreen(animateToken: _applicationsAnimToken),
          ProfileScreen(
            locale: widget.locale,
            animateToken: _profileAnimToken,
            onSettingsTap: _openSettings,
            onMyProfileTap: _openMyProfile,
            onBellTap: _openNotifications,
            onHelpTap: _openHelp,
            onRatingsTap: _openRatings,
            onMyScansTap: _openScans,
            onSavedScansTap: _openSavedScans,
            onPaymentsTap: _openPayments,
            onLoginTap: _openAuth,
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        items: items,
        onChanged: _onTabChanged,
      ),
    );
  }
}

class _ShellStrings {
  const _ShellStrings._();

  static List<AppBottomNavItem> items(Locale locale) => [
    AppBottomNavItem(
      label: _home(locale),
      iconAsset: 'assets/icons/tab-home.svg',
    ),
    AppBottomNavItem(
      label: _services(locale),
      iconAsset: 'assets/icons/tab-services.svg',
    ),
    AppBottomNavItem(
      label: _market(locale),
      iconAsset: 'assets/icons/tab-market.svg',
    ),
    AppBottomNavItem(
      label: _applications(locale),
      iconAsset: 'assets/icons/tab-applications.svg',
    ),
    AppBottomNavItem(
      label: _profile(locale),
      iconAsset: 'assets/icons/tab-profile.svg',
    ),
  ];

  static String _home(Locale l) => switch (l.languageCode) {
    'ru' => 'Главная',
    'en' => 'Home',
    _ => 'Asosiy',
  };

  static String _services(Locale l) => switch (l.languageCode) {
    'ru' => 'Услуги',
    'en' => 'Services',
    _ => 'Xizmatlar',
  };

  static String _market(Locale l) => switch (l.languageCode) {
    'ru' => 'Маркет',
    'en' => 'Market',
    _ => 'Market',
  };

  static String _applications(Locale l) => switch (l.languageCode) {
    'ru' => 'Заявки',
    'en' => 'Applications',
    _ => 'Arizalar',
  };

  static String _profile(Locale l) => switch (l.languageCode) {
    'ru' => 'Профиль',
    'en' => 'Profile',
    _ => 'Profil',
  };
}
