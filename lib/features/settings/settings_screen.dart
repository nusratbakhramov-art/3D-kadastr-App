import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_menu_card.dart';
import '../../widgets/app_reveal.dart';
import 'settings_state.dart';

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
          backgroundColor: AppColors.lightBackground,
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
              onChanged: (v) => notificationsEnabledNotifier.value = v,
            ),
            onTap: () => notificationsEnabledNotifier.value = !on,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: biometricEnabledNotifier,
          builder: (context, on, _) => AppMenuRow(
            icon: Icons.fingerprint_rounded,
            label: _S.biometric(locale),
            trailing: Switch.adaptive(
              value: on,
              onChanged: (v) => biometricEnabledNotifier.value = v,
            ),
            onTap: () => biometricEnabledNotifier.value = !on,
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
          onTap: () {},
        ),
        AppMenuRow(
          icon: Icons.description_outlined,
          label: _S.terms(locale),
          onTap: () {},
        ),
        AppMenuRow(
          icon: Icons.shield_outlined,
          label: _S.privacyPolicy(locale),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _otherCard(BuildContext context, Locale locale) {
    return AppMenuCard(
      rows: [
        AppMenuRow(
          icon: Icons.star_outline_rounded,
          label: _S.rateApp(locale),
          onTap: () {},
        ),
        AppMenuRow(
          icon: Icons.info_outline_rounded,
          label: _S.version(locale),
          trailing: const _ValueChip(text: '1.0.0'),
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
      backgroundColor: Colors.white,
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
    if (selected != null) localeNotifier.value = selected;
  }

  Future<void> _openThemeSheet(BuildContext context) async {
    final locale = localeNotifier.value;
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: Colors.white,
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
    if (selected != null) themeModeNotifier.value = selected;
  }

  Future<void> _confirmLogout(BuildContext context, Locale locale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _S.logoutTitle(locale),
          style: const TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textBlack,
          ),
        ),
        content: Text(
          _S.logoutMessage(locale),
          style: const TextStyle(
            fontFamily: 'MTSText',
            fontSize: 14,
            color: AppColors.textBlack,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _S.cancel(locale),
              style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                color: AppColors.textBlack,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _S.logout(locale),
              style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                color: Color(0xFFE5484D),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onLogoutConfirmed?.call();
    }
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
          color: AppColors.textBlack.withValues(alpha: 0.55),
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
            color: AppColors.textBlack.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.textBlack.withValues(alpha: 0.35),
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
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.textBlack,
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
                          style: const TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: AppColors.textBlack,
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
                              color: const Color(0xFFCCCFCD),
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
}
