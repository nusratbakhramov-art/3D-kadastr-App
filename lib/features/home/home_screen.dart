import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../onboarding/onboarding_page_data.dart';
import 'user_profile.dart';
import 'widgets/home_card.dart';
import 'widgets/home_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.locale = AppLocale.uz, this.today});

  final Locale locale;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final date = today ?? DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.greenBlack,
      body: SafeArea(
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
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              const _CardsGrid(),
            ],
          ),
        ),
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
