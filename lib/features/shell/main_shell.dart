import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_page_data.dart';
import 'app_bottom_nav.dart';
import 'placeholder_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.locale = AppLocale.uz});

  final Locale locale;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final items = _ShellStrings.items(widget.locale);

    return Scaffold(
      backgroundColor: AppColors.greenBlack,
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(locale: widget.locale),
          PlaceholderScreen(title: items[1].label),
          PlaceholderScreen(title: items[2].label),
          PlaceholderScreen(title: items[3].label),
          PlaceholderScreen(title: items[4].label),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        items: items,
        onChanged: (i) => setState(() => _index = i),
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
