import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../onboarding/onboarding_page_data.dart';
import 'user_profile.dart';
import 'widgets/home_card.dart';
import 'widgets/home_cta.dart';
import 'widgets/home_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.locale = AppLocale.uz,
    this.today,
    this.onLoginTap,
  });

  final Locale locale;
  final DateTime? today;
  final VoidCallback? onLoginTap;

  @override
  Widget build(BuildContext context) {
    final date = today ?? DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppColors.greenBlack
        : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _HomePatternBackground(
            backgroundColor: backgroundColor,
            showPattern: !isDark,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                            locale: locale,
                            today: date,
                            onLoginTap: onLoginTap,
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const _CardsGrid(),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<UserProfile?>(
                    valueListenable: userProfileNotifier,
                    builder: (context, profile, _) {
                      return HomeCta(
                        isGuest: profile == null,
                        locale: locale,
                        onLoginTap: onLoginTap,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
          final patternHeight = constraints.maxHeight * (2 / 3);

          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: backgroundColor),
                ),
              ),
              if (showPattern)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: patternHeight,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned(
                          top: -52,
                          right: -190,
                          child: Opacity(
                            opacity: 0.32,
                            child: Image.asset(
                              'assets/images/home/pattern.png',
                              width: constraints.maxWidth * 2.1,
                              fit: BoxFit.cover,
                              alignment: Alignment.topRight,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, backgroundColor],
                                stops: const [0.76, 1.0],
                              ),
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
    );
  }
}

class _CardsGrid extends StatelessWidget {
  const _CardsGrid();

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    const height = 97.0;

    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: HomeCard(
                  title: '3D kadastr',
                  iconAsset: 'assets/images/home/card-3d.svg',
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: HomeCard(
                  title: 'AI baholash',
                  iconAsset: 'assets/images/home/card-ai.svg',
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: gap),
        SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: HomeCard(
                  title: 'Kalkulyator',
                  iconAsset: 'assets/images/home/card-calculator.svg',
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: HomeCard(
                  title: 'Market',
                  iconAsset: 'assets/images/home/card-market.svg',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
