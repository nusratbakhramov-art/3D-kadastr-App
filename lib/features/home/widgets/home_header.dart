import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
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
    this.onAvatarTap,
  });

  final UserProfile? profile;
  final int unreadCount;
  final Locale locale;
  final DateTime today;
  final VoidCallback? onBellTap;
  final VoidCallback? onLoginTap;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGuest = profile == null;
    final greeting = isGuest
        ? _HomeStrings.guestGreeting(locale)
        : _HomeStrings.userGreeting(locale, profile!.name);
    final dateText = _HomeStrings.formatDate(locale, today);
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final dateColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : AppColors.textBlack.withValues(alpha: 0.55);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Avatar(profile: profile, onTap: onAvatarTap),
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
                ).copyWith(color: titleColor),
              ),
              const SizedBox(height: 2),
              Text(
                dateText,
                // One line, like the greeting above it. At the large
                // accessibility text sizes "23 sentabr, 2026" wrapped to two
                // lines and overflowed the header, which Home pins to a
                // computed height.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  height: 1.2,
                  color: dateColor,
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
          _BellButton(
            hasUnread: unreadCount > 0,
            isDark: isDark,
            onTap: onBellTap,
          ),
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
        onTap: hapticTap(onTap),
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
  const _Avatar({required this.profile, this.onTap});

  final UserProfile? profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final path = profile?.avatarPath;
    Widget avatar;
    if (path != null) {
      final isAsset = path.startsWith('assets/');
      avatar = ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: isAsset
              ? Image.asset(path, fit: BoxFit.cover)
              : Image.file(File(path), fit: BoxFit.cover),
        ),
      );
    } else if (profile == null) {
      avatar = Container(
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
    } else {
      final initial = profile!.name.isNotEmpty
          ? profile!.name.characters.first.toUpperCase()
          : '?';
      avatar = Container(
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

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: hapticTap(onTap),
        child: avatar,
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({
    required this.hasUnread,
    required this.isDark,
    required this.onTap,
  });

  final bool hasUnread;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dotBorderColor = isDark ? const Color(0xFF000702) : Colors.white;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: hapticTap(onTap),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Real 3D-rendered bell asset (green), sized to a 48pt footprint
            // so the tap target and unread dot stay put.
            SizedBox(
              width: 48,
              height: 48,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Image.asset(
                  'assets/icons/notification-icon.png',
                  fit: BoxFit.contain,
                ),
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
                    border: Border.all(color: dotBorderColor, width: 2),
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

  static String userGreeting(Locale locale, String name) {
    final prefix = tr(locale, 'home.header.greeting_prefix');
    return '$prefix, $name👋';
  }

  static String guestGreeting(Locale locale) =>
      tr(locale, 'home.header.guest_greeting');

  static String loginLabel(Locale locale) => tr(locale, 'home.header.login');

  static String formatDate(Locale locale, DateTime date) {
    final month = _monthName(locale, date.month);
    return '${date.day} $month, ${date.year}';
  }

  static String _monthName(Locale locale, int month) {
    const keys = [
      'home.month.jan',
      'home.month.feb',
      'home.month.mar',
      'home.month.apr',
      'home.month.may',
      'home.month.jun',
      'home.month.jul',
      'home.month.aug',
      'home.month.sep',
      'home.month.oct',
      'home.month.nov',
      'home.month.dec',
    ];
    final i = (month - 1).clamp(0, 11);
    return tr(locale, keys[i]);
  }
}
