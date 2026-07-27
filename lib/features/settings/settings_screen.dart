import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_review/in_app_review.dart';

import '../../core/api_config.dart';
import '../../core/app_version.dart';
import '../../core/haptics.dart';
import '../../core/i18n.dart';
import '../../core/i18n/app_translations.dart';
import '../auth/auth_http_client.dart';
import '../auth/widgets/login_required_sheet.dart';
import '../home/user_profile.dart' show paymentsHidden;
import '../payments/my_payments_screen.dart';

import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_menu_card.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_toast.dart';
import 'locale_storage.dart';
import 'theme_storage.dart';
import 'settings_state.dart';

const _kAppStoreId = '6744487945';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.onLogoutConfirmed,
    this.onAccountDeleted,
  });

  /// Called after the user confirms the logout dialog. The screen itself does
  /// not clear auth — the host wires that up.
  final VoidCallback? onLogoutConfirmed;

  /// Called after the account is successfully deleted on the backend. Falls
  /// back to [onLogoutConfirmed] if not provided.
  final VoidCallback? onAccountDeleted;

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
        // TODO: enable when biometric lock is implemented
        // ValueListenableBuilder<bool>(
        //   valueListenable: biometricEnabledNotifier,
        //   builder: (context, on, _) => AppMenuRow(
        //     icon: Icons.fingerprint_rounded,
        //     label: _S.biometric(locale),
        //     trailing: Switch.adaptive(
        //       value: on,
        //       onChanged: (v) => _toggleBiometric(context, locale, v),
        //     ),
        //     onTap: () => _toggleBiometric(context, locale, !on),
        //   ),
        // ),
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
          onTap: () => _openLegalSheet(context, locale, 'terms'),
        ),
        AppMenuRow(
          icon: Icons.shield_outlined,
          label: _S.privacyPolicy(locale),
          onTap: () => _openLegalSheet(context, locale, 'privacy'),
        ),
      ],
    );
  }

  Future<void> _openPayments(BuildContext context, Locale locale) async {
    if (!await ensureLoggedIn(context, message: _S.paymentsLoginMsg(locale))) {
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MyPaymentsScreen()));
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

  Future<void> _openLegalSheet(
    BuildContext context,
    Locale locale,
    String type,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LegalContentSheet(locale: locale, type: type),
    );
  }

  Widget _otherCard(BuildContext context, Locale locale) {
    return AppMenuCard(
      rows: [
        // Reviewer (demo) akkaunti uchun "To'lovlarim" ko'rsatilmaydi.
        if (!paymentsHidden)
          AppMenuRow(
            icon: Icons.receipt_long_outlined,
            label: _S.payments(locale),
            onTap: () => _openPayments(context, locale),
          ),
        AppMenuRow(
          icon: Icons.star_outline_rounded,
          label: _S.rateApp(locale),
          onTap: _openRateApp,
        ),
        AppMenuRow(
          icon: Icons.info_outline_rounded,
          label: _S.version(locale),
          // Was a hardcoded '1.0.0 (4)' — two releases stale, and disagreeing
          // with the About screen's own hardcoded copy. One source now.
          trailing: const _ValueChip(text: kAppVersionFull, showChevron: false),
          onTap: null,
        ),
        AppMenuRow(
          icon: Icons.logout_rounded,
          label: _S.logout(locale),
          destructive: true,
          onTap: () => _confirmLogout(context, locale),
        ),
        AppMenuRow(
          icon: Icons.delete_outline_rounded,
          label: _S.deleteAccount(locale),
          destructive: true,
          onTap: () => _confirmDeleteAccount(context, locale),
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

  // void _toggleBiometric(BuildContext context, Locale locale, bool v) {
  //   biometricEnabledNotifier.value = v;
  //   AppToast.success(context, _S.savedToast(locale));
  // }

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
      // Persist so the choice survives an app restart (like the locale does).
      await const ThemeStorage().save(selected);
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

  // Hisobni o'chirish (App Store 5.1.1(v)). Backend hisobni deaktivatsiya qilib
  // barcha sessiyalarni bekor qiladi; muvaffaqiyatda login ekraniga qaytamiz.
  Future<void> _confirmDeleteAccount(
    BuildContext context,
    Locale locale,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: ColorTokens.cardBg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _DeleteAccountSheet(locale: locale),
    );
    if (confirmed != true || !mounted) return;
    try {
      final res = await AuthHttpClient()
          .delete(Uri.parse('${ApiConfig.baseUrl}/profile/'))
          .timeout(const Duration(seconds: 15));
      if (!context.mounted) return;
      if (res.statusCode == 200) {
        AppToast.success(context, _S.deleteSuccess(locale));
        (widget.onAccountDeleted ?? widget.onLogoutConfirmed)?.call();
      } else {
        AppToast.error(context, _S.deleteError(locale));
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, _S.deleteError(locale));
      }
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

class _DeleteAccountSheet extends StatelessWidget {
  const _DeleteAccountSheet({required this.locale});

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
                decoration: const BoxDecoration(
                  color: Color(0xFFFDE8E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFE5484D),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _S.deleteAccountTitle(locale),
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
              _S.deleteAccountBody(locale),
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
                    label: _S.deleteConfirm(locale),
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
        onTap: hapticTap(onTap),
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/send-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        setState(() {
          _otpSent = true;
          _loading = false;
        });
      } else {
        setState(() {
          _error = L.errorOccurred(localeNotifier.value);
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = L.errorOccurred(localeNotifier.value);
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    final phone = _phoneCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    if (phone.isEmpty || otp.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = AuthHttpClient();
      final res = await client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/profile/change-phone'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'new_phone': phone, 'otp_code': otp}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          final locale = localeNotifier.value;
          AppToast.success(context, _S.phoneUpdated(locale));
        }
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _error =
              (body['detail'] as String?) ??
              L.errorOccurred(localeNotifier.value);
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = L.errorOccurred(localeNotifier.value);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: ColorTokens.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ColorTokens.secondaryText(
                    context,
                  ).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _S.phoneTitle(locale),
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
                  hintText: _S.otpHint(locale),
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
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: hapticTap(_loading ? null : (_otpSent ? _confirm : _sendOtp)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.splashGreen,
                foregroundColor: const Color(0xFF011606),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _otpSent
                          ? _S.phoneConfirm(localeNotifier.value)
                          : _S.sendOtp(localeNotifier.value),
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legal Content Sheet  (terms / privacy — fetched from API, cached per session)
// ─────────────────────────────────────────────────────────────────────────────

class _LegalFallback {
  static ({String title, String content}) get(String type, Locale l) {
    if (type == 'terms') {
      return (
        title: tr(l, 'settings.legal.terms_title'),
        content: tr(l, 'settings.legal.terms_body'),
      );
    }
    return (
      title: tr(l, 'settings.legal.privacy_title'),
      content: tr(l, 'settings.legal.privacy_body'),
    );
  }
}

class _LegalCache {
  static ({String title, String content})? terms;
  static ({String title, String content})? privacy;
}

class _LegalContentSheet extends StatefulWidget {
  const _LegalContentSheet({required this.locale, required this.type});
  final Locale locale;
  final String type;

  @override
  State<_LegalContentSheet> createState() => _LegalContentSheetState();
}

class _LegalContentSheetState extends State<_LegalContentSheet> {
  String? _title;
  String? _content;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final cached = widget.type == 'terms'
        ? _LegalCache.terms
        : _LegalCache.privacy;
    if (cached != null) {
      if (mounted)
        setState(() {
          _title = cached.title;
          _content = cached.content;
          _loading = false;
        });
      return;
    }
    try {
      final res = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/legal/${widget.type}?lang=${widget.locale.languageCode}',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final title = body['title'] as String;
        final content = body['content'] as String;
        if (widget.type == 'terms') {
          _LegalCache.terms = (title: title, content: content);
        } else {
          _LegalCache.privacy = (title: title, content: content);
        }
        if (mounted)
          setState(() {
            _title = title;
            _content = content;
            _loading = false;
          });
        return;
      }
    } catch (_) {
      // fall through to static fallback
    }
    // API unavailable — show static fallback content
    final fallback = _LegalFallback.get(widget.type, widget.locale);
    if (mounted)
      setState(() {
        _title = fallback.title;
        _content = fallback.content;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ColorTokens.secondaryText(
                  context,
                ).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 32,
                      color: ColorTokens.secondaryText(context),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        unawaited(_load());
                      },
                      child: Text(L.retry(Localizations.localeOf(context))),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                _title ?? '',
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: ColorTokens.primaryText(context),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + safeBottom),
                child: HtmlWidget(
                  _content ?? '',
                  textStyle: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 14,
                    height: 1.6,
                    color: ColorTokens.primaryText(context),
                  ),
                ),
              ),
            ),
          ],
        ],
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
  const _ValueChip({required this.text, this.showChevron = true});

  final String text;
  final bool showChevron;

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
        if (showChevron) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: ColorTokens.tertiaryText(context),
          ),
        ],
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
                onTap: hapticSelect(() => Navigator.pop(context, option)),
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

  static String _t(Locale l, String key) => tr(l, key);

  static String title(Locale l) => _t(l, 'settings.title');
  static String account(Locale l) => _t(l, 'settings.account');
  static String privacy(Locale l) => _t(l, 'settings.privacy');
  static String other(Locale l) => _t(l, 'settings.other');
  static String language(Locale l) => _t(l, 'settings.language');
  static String theme(Locale l) => _t(l, 'settings.theme');
  static String notifications(Locale l) => _t(l, 'settings.notifications');
  static String changePhone(Locale l) => _t(l, 'settings.change_phone');
  static String terms(Locale l) => _t(l, 'settings.terms');
  static String privacyPolicy(Locale l) => _t(l, 'settings.privacy_policy');
  static String payments(Locale l) => _t(l, 'settings.payments');
  static String paymentsLoginMsg(Locale l) =>
      _t(l, 'settings.payments_login_msg');
  static String rateApp(Locale l) => _t(l, 'settings.rate_app');
  static String version(Locale l) => _t(l, 'settings.version');
  static String logout(Locale l) => _t(l, 'settings.logout');
  static String logoutTitle(Locale l) => _t(l, 'settings.logout_title');
  static String logoutMessage(Locale l) => _t(l, 'settings.logout_message');
  static String cancel(Locale l) => _t(l, 'common.cancel');

  static String deleteAccount(Locale l) => _t(l, 'settings.delete_account');
  static String deleteSuccess(Locale l) =>
      _t(l, 'settings.dialog.delete_success');
  static String deleteError(Locale l) => _t(l, 'settings.dialog.delete_error');
  static String deleteAccountTitle(Locale l) =>
      _t(l, 'settings.dialog.delete_account_title');
  static String deleteAccountBody(Locale l) =>
      _t(l, 'settings.dialog.delete_account_body');
  static String deleteConfirm(Locale l) =>
      _t(l, 'settings.dialog.delete_confirm');

  static String phoneTitle(Locale l) => _t(l, 'settings.phone.title');
  static String otpHint(Locale l) => _t(l, 'settings.phone.otp_hint');
  static String phoneUpdated(Locale l) => _t(l, 'settings.phone.updated');
  static String phoneConfirm(Locale l) => _t(l, 'settings.phone.confirm');
  static String sendOtp(Locale l) => _t(l, 'settings.phone.send_otp');

  static String languageName(Locale l) => _t(l, 'settings.language_name');
  static String themeName(Locale l, ThemeMode mode) => switch (mode) {
    ThemeMode.system => _t(l, 'settings.theme_name.system'),
    ThemeMode.light => _t(l, 'settings.theme_name.light'),
    ThemeMode.dark => _t(l, 'settings.theme_name.dark'),
  };
  static String savedToast(Locale l) => _t(l, 'common.saved');
}
