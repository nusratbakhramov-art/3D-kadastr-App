import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/app_translations.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_bell_button.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_menu_card.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_toast.dart';
import '../home/user_profile.dart';
import '../market/widgets/listing_cta_button.dart';
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
    this.onAboutTap,
    this.onLoginTap,
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
  final VoidCallback? onAboutTap;

  /// Foydalanuvchi tizimga kirmagan (`profile == null` yoki bo'sh) bo'lsa,
  /// menyu o'rniga "Kirish" tugmasi shu callback'ni chaqiradi.
  final VoidCallback? onLoginTap;

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

    // Tizimga kirgan foydalanuvchi uchun to'liq menyu.
    final authedRows = <_RowSpec>[
      _RowSpec(
        'assets/icons/menu-profile.svg',
        _ProfileStrings.myProfile(locale),
        widget.onMyProfileTap,
      ),
      _RowSpec(
        'assets/icons/menu-scan-3d.svg',
        _ProfileStrings.scan(locale),
        () => _openScanPicker(context),
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
      // Reviewer (demo) akkaunti uchun "To'lovlar" ko'rsatilmaydi.
      if (!paymentsHidden)
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
      _RowSpec(
        'assets/icons/menu-about.svg',
        _ProfileStrings.aboutApp(locale),
        widget.onAboutTap,
      ),
    ];

    // Mehmon (login qilmagan) uchun cheklangan menyu — faqat Sozlamalar +
    // Yordam. "Skan qilish" hozircha auth'siz ham ko'rinadi (vaqtinchalik).
    final guestRows = <_RowSpec>[
      _RowSpec(
        'assets/icons/menu-scan-3d.svg',
        _ProfileStrings.scan(locale),
        () => _openScanPicker(context),
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
      _RowSpec(
        'assets/icons/menu-about.svg',
        _ProfileStrings.aboutApp(locale),
        widget.onAboutTap,
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
                // Foydalanuvchi tizimga kirgani — profile bor va ismi bo'sh
                // emas. Boshqa hollarda mehmon hisoblanadi.
                final isAuthed = profile != null && profile.name.trim().isNotEmpty;
                final rows = isAuthed ? authedRows : guestRows;
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
                          if (!isAuthed) ...[
                            AppReveal(
                              controller: entryController,
                              interval: const Interval(
                                0.32,
                                0.85,
                                curve: Curves.easeOutCubic,
                              ),
                              child: ListingCtaButton(
                                label: _ProfileStrings.login(locale),
                                onTap: widget.onLoginTap ?? () {},
                              ),
                            ),
                            const SizedBox(height: 8),
                            AppReveal(
                              controller: entryController,
                              interval: const Interval(
                                0.4,
                                0.9,
                                curve: Curves.easeOutCubic,
                              ),
                              child: Text(
                                _ProfileStrings.guestHint(locale),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'MTSText',
                                  fontSize: 13,
                                  height: 1.35,
                                  color: ColorTokens.secondaryText(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
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

  /// "Skan qilish" bosilganda — qaysi skan modelidan foydalanishni tanlash
  /// varag'ini ochadi. Hozircha #1 / #2 variantlari (onTap'lar bo'sh —
  /// keyinroq ulanadi).
  Future<void> _openScanPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ColorTokens.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ScanPickerSheet(locale: widget.locale),
    );
  }
}

/// "Skan qilish" varag'i — foydalanuvchi skan modelini tanlaydi.
/// "#2" → PCScan (RoomPlan+ObjectCapture), iOS 17+/LiDAR native skaner.
class _ScanPickerSheet extends StatelessWidget {
  const _ScanPickerSheet({required this.locale});

  final Locale locale;

  /// Native PCScan (RoomPlan+ObjectCapture) skanerini ochadigan kanal
  /// (iOS, faqat 17+/LiDAR).
  static const MethodChannel _pcscanScanner = MethodChannel(
    'kadastr/pcscan_scanner',
  );

  /// "#2" — PCScan skanerini ochadi.
  Future<void> _openPcscan(BuildContext context) async {
    try {
      await _pcscanScanner.invokeMethod('open');
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, _ProfileStrings.scanUnsupported(locale));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ColorTokens.divider(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _ProfileStrings.scanPickerTitle(locale),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: ColorTokens.primaryText(context),
                ),
              ),
            ),
            const SizedBox(height: 8),
            AppMenuRow(
              icon: Icons.looks_two_outlined,
              label: '#2',
              onTap: () => _openPcscan(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowSpec {
  const _RowSpec(this.iconAsset, this.label, this.onTap) : icon = null;
  const _RowSpec.icon(this.icon, this.label, this.onTap) : iconAsset = null;
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

  static String scan(Locale l) =>
      tr(l, 'profile.scan', uz: 'Skan qilish', ru: 'Сканировать', en: 'Scan');

  static String scanPickerTitle(Locale l) => tr(
    l,
    'profile.scan_picker_title',
    uz: 'Skan modelini tanlang',
    ru: 'Выберите модель сканирования',
    en: 'Choose scan model',
  );

  static String scanUnsupported(Locale l) => tr(
    l,
    'profile.scan_unsupported',
    uz: 'Skan bu qurilmada mavjud emas (iOS 17+ va LiDAR kerak)',
    ru: 'Сканирование недоступно на этом устройстве (нужен iOS 17+ и LiDAR)',
    en: 'Scanning is unavailable on this device (needs iOS 17+ and LiDAR)',
  );

  static String myScans(Locale l) => switch (l.languageCode) {
    'ru' => 'Мои заявки',
    'en' => 'My applications',
    _ => 'Mening arizalarim',
  };

  static String aboutApp(Locale l) => tr(
    l,
    'profile.about_app',
    uz: 'Ilova haqida',
    ru: 'О приложении',
    en: 'About app',
  );

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

  static String login(Locale l) => switch (l.languageCode) {
    'ru' => 'Войти',
    'en' => 'Log in',
    _ => 'Kirish',
  };

  static String guestHint(Locale l) => switch (l.languageCode) {
    'ru' =>
        'Войдите, чтобы видеть свои сканирования, оценки и историю заказов.',
    'en' =>
        'Log in to see your scans, valuations and order history.',
    _ => 'Skanerlaringiz, baholashlaringiz va buyurtmalar tarixini ko\'rish '
        'uchun tizimga kiring.',
  };
}
