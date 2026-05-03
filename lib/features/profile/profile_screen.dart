import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_bell_button.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_menu_card.dart';
import '../../widgets/app_reveal.dart';
import '../home/user_profile.dart';
import '../onboarding/onboarding_page_data.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.locale = AppLocale.uz,
    this.animateToken = 0,
    this.onBellTap,
    this.onMyProfileTap,
    this.onMyScansTap,
    this.onRatingsTap,
    this.onPaymentsTap,
    this.onSettingsTap,
    this.onHelpTap,
  });

  final Locale locale;
  final int animateToken;
  final VoidCallback? onBellTap;
  final VoidCallback? onMyProfileTap;
  final VoidCallback? onMyScansTap;
  final VoidCallback? onRatingsTap;
  final VoidCallback? onPaymentsTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onHelpTap;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        RevealEntryMixin<ProfileScreen> {
  @override
  bool get wantKeepAlive => true;

  @override
  int get currentToken => widget.animateToken;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locale = widget.locale;
    final rows = <_RowSpec>[
      _RowSpec(
        'assets/icons/menu-profile.svg',
        _ProfileStrings.myProfile(locale),
        widget.onMyProfileTap,
      ),
      _RowSpec(
        'assets/icons/menu-scan.svg',
        _ProfileStrings.myScans(locale),
        widget.onMyScansTap,
      ),
      _RowSpec(
        'assets/icons/menu-ratings.svg',
        _ProfileStrings.ratings(locale),
        widget.onRatingsTap,
      ),
      _RowSpec(
        'assets/icons/menu-payments.svg',
        _ProfileStrings.payments(locale),
        widget.onPaymentsTap,
      ),
      _RowSpec(
        'assets/icons/menu-settings.svg',
        _ProfileStrings.settings(locale),
        widget.onSettingsTap,
      ),
      _RowSpec(
        'assets/icons/menu-help.svg',
        _ProfileStrings.help(locale),
        widget.onHelpTap,
      ),
    ];

    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppGlowBackground(),
          SafeArea(
            child: ValueListenableBuilder<UserProfile?>(
              valueListenable: userProfileNotifier,
              builder: (context, profile, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: notificationUnreadNotifier,
                  builder: (context, unread, _) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppReveal(
                            controller: entryController,
                            interval: const Interval(
                              0.0,
                              0.4,
                              curve: Curves.easeOutCubic,
                            ),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: AppBellButton(
                                hasUnread: unread > 0,
                                onTap: widget.onBellTap,
                                dotKey: const ValueKey('profile.bell.dot'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          AppReveal(
                            controller: entryController,
                            interval: const Interval(
                              0.1,
                              0.6,
                              curve: Curves.easeOutCubic,
                            ),
                            child: Center(
                              child: AppAvatar(
                                path: profile?.avatarPath,
                                name: profile?.name ?? '',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AppReveal(
                            controller: entryController,
                            interval: const Interval(
                              0.2,
                              0.7,
                              curve: Curves.easeOutCubic,
                            ),
                            child: Text(
                              profile?.name.isNotEmpty == true
                                  ? profile!.name
                                  : _ProfileStrings.guestName(locale),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                                height: 1.25,
                                color: ColorTokens.primaryText(context),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          AppReveal(
                            controller: entryController,
                            interval: const Interval(
                              0.25,
                              0.75,
                              curve: Curves.easeOutCubic,
                            ),
                            child: Text(
                              profile?.phone ?? '',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w400,
                                fontSize: 15,
                                height: 1.2,
                                color: ColorTokens.secondaryText(context),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          AppReveal(
                            controller: entryController,
                            interval: const Interval(
                              0.35,
                              1.0,
                              curve: Curves.easeOutCubic,
                            ),
                            child: AppMenuCard(
                              rows: [
                                for (var i = 0; i < rows.length; i++)
                                  AppReveal(
                                    controller: entryController,
                                    slideX: 16,
                                    slideY: 0,
                                    interval: Interval(
                                      0.45 + i * 0.06,
                                      (0.65 + i * 0.06).clamp(0.0, 1.0),
                                      curve: Curves.easeOutCubic,
                                    ),
                                    child: AppMenuRow(
                                      iconAsset: rows[i].iconAsset,
                                      icon: rows[i].icon,
                                      label: rows[i].label,
                                      onTap: rows[i].onTap,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RowSpec {
  const _RowSpec(this.iconAsset, this.label, this.onTap) : icon = null;
  final String? iconAsset;
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
}

class _ProfileStrings {
  const _ProfileStrings._();

  static String guestName(Locale l) => switch (l.languageCode) {
    'ru' => 'Гость',
    'en' => 'Guest',
    _ => 'Mehmon',
  };

  static String myProfile(Locale l) => switch (l.languageCode) {
    'ru' => 'Мой профиль',
    'en' => 'My profile',
    _ => 'Mening profilim',
  };

  static String myScans(Locale l) => switch (l.languageCode) {
    'ru' => 'Мои сканирования',
    'en' => 'My scans',
    _ => 'Mening skanerlarim',
  };

  static String ratings(Locale l) => switch (l.languageCode) {
    'ru' => 'Мои оценки',
    'en' => 'My ratings',
    _ => 'Baholashlarim',
  };

  static String payments(Locale l) => switch (l.languageCode) {
    'ru' => 'Платежи',
    'en' => 'Payments',
    _ => "To'lovlar",
  };

  static String settings(Locale l) => switch (l.languageCode) {
    'ru' => 'Настройки',
    'en' => 'Settings',
    _ => 'Sozlamalar',
  };

  static String help(Locale l) => switch (l.languageCode) {
    'ru' => 'Помощь',
    'en' => 'Help',
    _ => 'Yordam',
  };
}
