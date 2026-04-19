import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../user_profile.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.profile,
    required this.unreadCount,
    required this.locale,
    required this.today,
    this.onBellTap,
    this.onLoginTap,
  });

  final UserProfile? profile;
  final int unreadCount;
  final Locale locale;
  final DateTime today;
  final VoidCallback? onBellTap;
  final VoidCallback? onLoginTap;

  @override
  Widget build(BuildContext context) {
    final isGuest = profile == null;
    final greeting = isGuest
        ? _HomeStrings.guestGreeting(locale)
        : _HomeStrings.userGreeting(locale, profile!.name);
    final dateText = _HomeStrings.formatDate(locale, today);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Avatar(profile: profile),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                greeting,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  height: 1.3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateText,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  height: 1.2,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (isGuest)
          _LoginButton(
            label: _HomeStrings.loginLabel(locale),
            onTap: onLoginTap,
          )
        else
          _BellButton(hasUnread: unreadCount > 0, onTap: onBellTap),
      ],
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.splashGreen,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.2,
              color: AppColors.buttonTextBlack,
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final asset = profile?.avatarAsset;
    if (asset != null) {
      return ClipOval(
        child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover),
      );
    }

    if (profile == null) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF2A2F31),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.person_outline_rounded,
          size: 24,
          color: Colors.white70,
        ),
      );
    }

    final initial = profile!.name.isNotEmpty
        ? profile!.name.characters.first.toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF0A6B23),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.hasUnread, required this.onTap});

  final bool hasUnread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1F21),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),
            if (hasUnread)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  key: const ValueKey('home.bell.dot'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF000702),
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeStrings {
  const _HomeStrings._();

  static String userGreeting(Locale locale, String name) =>
      switch (locale.languageCode) {
        'ru' => 'Привет, $name👋',
        'en' => 'Hi, $name👋',
        _ => 'Salom, $name👋',
      };

  static String guestGreeting(Locale locale) => switch (locale.languageCode) {
    'ru' => 'Привет, гость👋',
    'en' => 'Hi, guest👋',
    _ => 'Salom, mehmon👋',
  };

  static String loginLabel(Locale locale) => switch (locale.languageCode) {
    'ru' => 'Войти',
    'en' => 'Log in',
    _ => 'Kirish',
  };

  static String formatDate(Locale locale, DateTime date) {
    final month = _monthName(locale, date.month);
    return '${date.day} $month, ${date.year}';
  }

  static String _monthName(Locale locale, int month) {
    const uz = [
      'yanvar',
      'fevral',
      'mart',
      'aprel',
      'may',
      'iyun',
      'iyul',
      'avgust',
      'sentabr',
      'oktabr',
      'noyabr',
      'dekabr',
    ];
    const ru = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    const en = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final i = (month - 1).clamp(0, 11);
    return switch (locale.languageCode) {
      'ru' => ru[i],
      'en' => en[i],
      _ => uz[i],
    };
  }
}
