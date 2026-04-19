import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../auth/auth_flow_screen.dart';
import '../auth/auth_storage.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_page_data.dart';
import 'app_bottom_nav.dart';
import 'placeholder_screen.dart';

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
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int i) {
    if (i == _index) return;
    final delta = (i - _index).abs();
    setState(() => _index = i);
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
  }

  @override
  Widget build(BuildContext context) {
    final items = _ShellStrings.items(widget.locale);

    return Scaffold(
      backgroundColor: AppColors.greenBlack,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) {
          if (i != _index) setState(() => _index = i);
        },
        children: [
          HomeScreen(locale: widget.locale, onLoginTap: _openAuth),
          PlaceholderScreen(title: items[1].label),
          PlaceholderScreen(title: items[2].label),
          PlaceholderScreen(title: items[3].label),
          PlaceholderScreen(title: items[4].label),
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
