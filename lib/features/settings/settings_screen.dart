import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_config.dart';
import '../auth/auth_http_client.dart';

import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_menu_card.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_toast.dart';
import 'locale_storage.dart';
import 'settings_state.dart';

const _kTermsUrl = 'https://3dkadastr.uz/terms';
const _kPrivacyUrl = 'https://3dkadastr.uz/privacy';
const _kAppStoreId = '6744487945';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onLogoutConfirmed});

  /// Called after the user confirms the logout dialog. The screen itself does
  /// not clear auth — the host wires that up.
  final VoidCallback? onLogoutConfirmed;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<SettingsScreen> {
  @override
  int get currentToken => 1;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return Scaffold(
          backgroundColor: ColorTokens.scaffoldBg(context),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const AppGlowBackground(),
              SafeArea(
                child: SingleChildScrollView(
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
                        child: AppHeaderBack(title: _S.title(locale)),
                      ),
                      const SizedBox(height: 16),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.1,
                          0.6,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _SectionLabel(text: _S.account(locale)),
                      ),
                      const SizedBox(height: 8),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.15,
                          0.7,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _accountCard(context, locale),
                      ),
                      const SizedBox(height: 16),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.25,
                          0.75,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _SectionLabel(text: _S.privacy(locale)),
                      ),
                      const SizedBox(height: 8),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.3,
                          0.85,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _privacyCard(locale),
                      ),
                      const SizedBox(height: 16),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.4,
                          0.9,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _SectionLabel(text: _S.other(locale)),
                      ),
                      const SizedBox(height: 8),
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.45,
                          1.0,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _otherCard(context, locale),
                      ),
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

  Widget _accountCard(BuildContext context, Locale locale) {
    return AppMenuCard(
      rows: [
        ValueListenableBuilder<Locale>(
          valueListenable: localeNotifier,
          builder: (context, current, _) => AppMenuRow(
            icon: Icons.translate_rounded,
            label: _S.language(locale),
            trailing: _ValueChip(text: _S.languageName(current)),
            onTap: () => _openLanguageSheet(context),
          ),
        ),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, mode, _) => AppMenuRow(
            icon: Icons.brightness_6_rounded,
            label: _S.theme(locale),
            trailing: _ValueChip(text: _S.themeName(locale, mode)),
            onTap: () => _openThemeSheet(context),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: notificationsEnabledNotifier,
          builder: (context, on, _) => AppMenuRow(
            icon: Icons.notifications_active_outlined,
            label: _S.notifications(locale),
            trailing: Switch.adaptive(
              value: on,
              onChanged: (v) => _toggleNotifications(context, locale, v),
            ),
            onTap: () => _toggleNotifications(context, locale, !on),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: biometricEnabledNotifier,
          builder: (context, on, _) => AppMenuRow(
            icon: Icons.fingerprint_rounded,
            label: _S.biometric(locale),
            trailing: Switch.adaptive(
              value: on,
              onChanged: (v) => _toggleBiometric(context, locale, v),
            ),
            onTap: () => _toggleBiometric(context, locale, !on),
          ),
        ),
      ],
    );
  }

  Widget _privacyCard(Locale locale) {
    return AppMenuCard(
      rows: [
        AppMenuRow(
          icon: Icons.phone_iphone_rounded,
          label: _S.changePhone(locale),
          onTap: () => _openChangePhone(context, locale),
        ),
        AppMenuRow(
          icon: Icons.description_outlined,
          label: _S.terms(locale),
          onTap: () => _launchUrl(_kTermsUrl),
        ),
        AppMenuRow(
          icon: Icons.shield_outlined,
          label: _S.privacyPolicy(locale),
          onTap: () => _launchUrl(_kPrivacyUrl),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openRateApp() async {
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
    } else {
      await review.openStoreListing(appStoreId: _kAppStoreId);
    }
  }

  Future<void> _openChangePhone(BuildContext context, Locale locale) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangePhoneSheet(locale: locale),
    );
  }

  Widget _otherCard(BuildContext context, Locale locale) {
    return AppMenuCard(
      rows: [
        AppMenuRow(
          icon: Icons.star_outline_rounded,
          label: _S.rateApp(locale),
          onTap: _openRateApp,
        ),
        AppMenuRow(
          icon: Icons.info_outline_rounded,
          label: _S.version(locale),
          trailing: const _ValueChip(text: '1.0.0 (3)'),
          onTap: null,
        ),
        AppMenuRow(
          icon: Icons.logout_rounded,
          label: _S.logout(locale),
          destructive: true,
          onTap: () => _confirmLogout(context, locale),
        ),
      ],
    );
  }

  Future<void> _openLanguageSheet(BuildContext context) async {
    final locale = localeNotifier.value;
    final selected = await showModalBottomSheet<Locale>(
      context: context,
      backgroundColor: ColorTokens.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _OptionSheet<Locale>(
        title: _S.language(locale),
        current: localeNotifier.value,
        options: const [Locale('uz'), Locale('ru'), Locale('en')],
        labelOf: _S.languageName,
      ),
    );
    if (selected != null && selected != localeNotifier.value) {
      localeNotifier.value = selected;
      // Disk'ga saqlaymiz — keyingi ishga tushganda ham shu til ishlaydi.
      await const LocaleStorage().save(selected);
      if (!context.mounted) return;
      AppToast.success(context, _S.savedToast(selected));
    }
  }

  void _toggleNotifications(BuildContext context, Locale locale, bool v) {
    notificationsEnabledNotifier.value = v;
    AppToast.success(context, _S.savedToast(locale));
  }

  void _toggleBiometric(BuildContext context, Locale locale, bool v) {
    biometricEnabledNotifier.value = v;
    AppToast.success(context, _S.savedToast(locale));
  }

  Future<void> _openThemeSheet(BuildContext context) async {
    final locale = localeNotifier.value;
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: ColorTokens.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _OptionSheet<ThemeMode>(
        title: _S.theme(locale),
        current: themeModeNotifier.value,
        options: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
        labelOf: (m) => _S.themeName(locale, m),
      ),
    );
    if (selected != null && selected != themeModeNotifier.value) {
      themeModeNotifier.value = selected;
      if (!context.mounted) return;
      AppToast.success(context, _S.savedToast(locale));
    }
  }

  Future<void> _confirmLogout(BuildContext context, Locale locale) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: ColorTokens.cardBg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _LogoutSheet(locale: locale),
    );
    if (confirmed == true && mounted) {
      widget.onLogoutConfirmed?.call();
    }
  }
}

class _LogoutSheet extends StatelessWidget {
  const _LogoutSheet({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE8E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFE5484D),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _S.logoutTitle(locale),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 19,
                color: ColorTokens.primaryText(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _S.logoutMessage(locale),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 14,
                height: 1.4,
                color: ColorTokens.secondaryText(context),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: _S.cancel(locale),
                    onTap: () => Navigator.pop(context, false),
                    background: ColorTokens.iconBg(context),
                    foreground: ColorTokens.primaryText(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    label: _S.logout(locale),
                    onTap: () => Navigator.pop(context, true),
                    background: const Color(0xFFE5484D),
                    foreground: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Change Phone Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ChangePhoneSheet extends StatefulWidget {
  const _ChangePhoneSheet({required this.locale});
  final Locale locale;

  @override
  State<_ChangePhoneSheet> createState() => _ChangePhoneSheetState();
}

class _ChangePhoneSheetState extends State<_ChangePhoneSheet> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        setState(() { _otpSent = true; _loading = false; });
      } else {
        setState(() { _error = 'Xatolik yuz berdi'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _confirm() async {
    final phone = _phoneCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    if (phone.isEmpty || otp.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final client = AuthHttpClient();
      final res = await client.post(
        Uri.parse('${ApiConfig.baseUrl}/profile/change-phone'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'new_phone': phone, 'otp_code': otp}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          AppToast.success(context, 'Telefon raqam yangilandi');
        }
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() { _error = (body['detail'] as String?) ?? 'Xatolik yuz berdi'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: ColorTokens.secondaryText(context).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Telefon raqamni o\'zgartirish',
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: ColorTokens.primaryText(context),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              enabled: !_otpSent,
              decoration: InputDecoration(
                hintText: '+998 XX XXX XX XX',
                filled: true,
                fillColor: ColorTokens.iconBg(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: 'OTP kodi',
                  counterText: '',
                  filled: true,
                  fillColor: ColorTokens.iconBg(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : (_otpSent ? _confirm : _sendOtp),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.splashGreen,
                foregroundColor: const Color(0xFF011606),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      _otpSent ? 'Tasdiqlash' : 'OTP yuborish',
                      style: const TextStyle(fontFamily: 'MTSCompact', fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: ColorTokens.secondaryText(context),
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: ColorTokens.secondaryText(context),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: ColorTokens.tertiaryText(context),
        ),
      ],
    );
  }
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.current,
    required this.options,
    required this.labelOf,
  });

  final String title;
  final T current;
  final List<T> options;
  final String Function(T) labelOf;

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
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: ColorTokens.primaryText(context),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final option in options)
              InkWell(
                onTap: () => Navigator.pop(context, option),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          labelOf(option),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: ColorTokens.primaryText(context),
                          ),
                        ),
                      ),
                      if (option == current)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.brandGreen,
                          size: 22,
                        )
                      else
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ColorTokens.outline(context),
                              width: 1.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Настройки',
    'en' => 'Settings',
    _ => 'Sozlamalar',
  };
  static String account(Locale l) => switch (l.languageCode) {
    'ru' => 'Аккаунт',
    'en' => 'Account',
    _ => 'Hisob',
  };
  static String privacy(Locale l) => switch (l.languageCode) {
    'ru' => 'Конфиденциальность',
    'en' => 'Privacy',
    _ => 'Maxfiylik',
  };
  static String other(Locale l) => switch (l.languageCode) {
    'ru' => 'Прочее',
    'en' => 'Other',
    _ => 'Boshqa',
  };
  static String language(Locale l) => switch (l.languageCode) {
    'ru' => 'Язык',
    'en' => 'Language',
    _ => 'Til',
  };
  static String theme(Locale l) => switch (l.languageCode) {
    'ru' => 'Тема',
    'en' => 'Theme',
    _ => 'Mavzu',
  };
  static String notifications(Locale l) => switch (l.languageCode) {
    'ru' => 'Уведомления',
    'en' => 'Notifications',
    _ => 'Bildirishnomalar',
  };
  static String biometric(Locale l) => switch (l.languageCode) {
    'ru' => 'Биометрический вход',
    'en' => 'Biometric login',
    _ => 'Biometrik kirish',
  };
  static String changePhone(Locale l) => switch (l.languageCode) {
    'ru' => 'Сменить номер',
    'en' => 'Change phone',
    _ => 'Telefon raqamni o‘zgartirish',
  };
  static String terms(Locale l) => switch (l.languageCode) {
    'ru' => 'Условия использования',
    'en' => 'Terms of use',
    _ => 'Foydalanish shartlari',
  };
  static String privacyPolicy(Locale l) => switch (l.languageCode) {
    'ru' => 'Политика конфиденциальности',
    'en' => 'Privacy policy',
    _ => 'Maxfiylik siyosati',
  };
  static String rateApp(Locale l) => switch (l.languageCode) {
    'ru' => 'Оценить приложение',
    'en' => 'Rate the app',
    _ => 'Ilovani baholash',
  };
  static String version(Locale l) => switch (l.languageCode) {
    'ru' => 'Версия',
    'en' => 'Version',
    _ => 'Versiya',
  };
  static String logout(Locale l) => switch (l.languageCode) {
    'ru' => 'Выйти',
    'en' => 'Log out',
    _ => 'Chiqish',
  };
  static String logoutTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Выйти из аккаунта?',
    'en' => 'Log out?',
    _ => 'Chiqishni xohlaysizmi?',
  };
  static String logoutMessage(Locale l) => switch (l.languageCode) {
    'ru' => 'Вы можете снова войти в любое время.',
    'en' => 'You can sign in again anytime.',
    _ => 'Istalgan vaqtda qayta kirishingiz mumkin.',
  };
  static String cancel(Locale l) => switch (l.languageCode) {
    'ru' => 'Отмена',
    'en' => 'Cancel',
    _ => 'Bekor qilish',
  };

  static String languageName(Locale l) => switch (l.languageCode) {
    'ru' => 'Русский',
    'en' => 'English',
    _ => 'O‘zbekcha',
  };
  static String themeName(Locale l, ThemeMode mode) => switch (mode) {
    ThemeMode.system => switch (l.languageCode) {
      'ru' => 'Системная',
      'en' => 'System',
      _ => 'Tizim',
    },
    ThemeMode.light => switch (l.languageCode) {
      'ru' => 'Светлая',
      'en' => 'Light',
      _ => 'Yorug‘',
    },
    ThemeMode.dark => switch (l.languageCode) {
      'ru' => 'Тёмная',
      'en' => 'Dark',
      _ => 'Tungi',
    },
  };
  static String savedToast(Locale l) => switch (l.languageCode) {
    'ru' => 'Сохранено',
    'en' => 'Saved',
    _ => 'Saqlandi',
  };
}
