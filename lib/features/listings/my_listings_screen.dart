import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_reveal.dart';
import '../ratings/valuation_model.dart' show formatSum, formatShortDate;
import '../settings/settings_state.dart';
import 'listing_model.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key, this.animateToken = 0});

  final int animateToken;

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        RevealEntryMixin<MyListingsScreen> {
  @override
  bool get wantKeepAlive => true;

  @override
  int get currentToken => widget.animateToken;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        final items = mockListings;
        return Scaffold(
          backgroundColor: ColorTokens.scaffoldBg(context),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const AppGlowBackground(),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                        child: _Header(locale: locale),
                      ),
                      const SizedBox(height: 16),
                      if (items.isEmpty)
                        _EmptyState(
                          title: _S.emptyTitle(locale),
                          message: _S.emptyMessage(locale),
                          ctaLabel: _S.create(locale),
                        )
                      else
                        for (var i = 0; i < items.length; i++) ...[
                          AppReveal(
                            controller: entryController,
                            interval: Interval(
                              (0.1 + i * 0.06).clamp(0.0, 0.9),
                              (0.6 + i * 0.06).clamp(0.0, 1.0),
                              curve: Curves.easeOutCubic,
                            ),
                            child: _ListingCard(item: items[i], locale: locale),
                          ),
                          if (i != items.length - 1) const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _S.title(locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 22,
              color: ColorTokens.primaryText(context),
            ),
          ),
        ),
        Material(
          color: AppColors.brandGreen,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: hapticTap(() {}),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    _S.create(locale),
                    style: const TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.item, required this.locale});

  final MyListing item;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.cardBg(context),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(() {}),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(accent: item.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: ColorTokens.primaryText(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(status: item.status, locale: locale),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: ColorTokens.secondaryText(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatSum(item.priceUzs),
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: ColorTokens.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _MetaPill(
                          icon: Icons.straighten_rounded,
                          text: '${_fmt(item.areaSqm)} m²',
                        ),
                        const SizedBox(width: 6),
                        _MetaPill(
                          icon: Icons.visibility_outlined,
                          text: '${item.views}',
                        ),
                        const SizedBox(width: 6),
                        _MetaPill(
                          icon: Icons.calendar_month_outlined,
                          text: formatShortDate(item.at),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _ActionButton(
                          icon: Icons.qr_code_2_rounded,
                          label: 'QR',
                          onTap: () {},
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.threed_rotation_rounded,
                          label: 'AR',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.home_work_rounded,
        size: 36,
        color: accent.withValues(alpha: 0.65),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.locale});

  final ListingStatus status;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      ListingStatus.moderation => (
        _S.statusModeration(locale),
        const Color(0xFFF59E0B),
      ),
      ListingStatus.approved => (
        _S.statusApproved(locale),
        const Color(0xFF10B981),
      ),
      ListingStatus.rejected => (
        _S.statusRejected(locale),
        const Color(0xFFEF4444),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: color,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ColorTokens.iconBg(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: ColorTokens.secondaryText(context),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: ColorTokens.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.primaryText(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: hapticTap(onTap),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: ColorTokens.cardBg(context)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: ColorTokens.cardBg(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.message,
    required this.ctaLabel,
  });

  final String title;
  final String message;
  final String ctaLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: ColorTokens.cardBg(context),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: ColorTokens.shadow(context),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.home_work_outlined,
              size: 28,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              color: ColorTokens.secondaryText(context),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: AppColors.brandGreen,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: hapticTap(() {}),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ctaLabel,
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Мои объявления',
    'en' => 'My listings',
    _ => 'Mening e‘lonlarim',
  };
  static String create(Locale l) => switch (l.languageCode) {
    'ru' => 'Создать',
    'en' => 'Create',
    _ => 'Yangi',
  };
  static String statusModeration(Locale l) => switch (l.languageCode) {
    'ru' => 'На модерации',
    'en' => 'In moderation',
    _ => 'Moderatsiyada',
  };
  static String statusApproved(Locale l) => switch (l.languageCode) {
    'ru' => 'Одобрено',
    'en' => 'Approved',
    _ => 'Tasdiqlangan',
  };
  static String statusRejected(Locale l) => switch (l.languageCode) {
    'ru' => 'Отклонено',
    'en' => 'Rejected',
    _ => 'Rad etilgan',
  };
  static String emptyTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Объявлений пока нет',
    'en' => 'No listings yet',
    _ => 'Hali e‘lon yo‘q',
  };
  static String emptyMessage(Locale l) => switch (l.languageCode) {
    'ru' => 'Создайте первое 3D объявление на основе ваших сканов.',
    'en' => 'Create your first 3D listing from your scans.',
    _ => 'Skanlaringiz asosida birinchi 3D e‘lonni yarating.',
  };
}
