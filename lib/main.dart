import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'features/auth/auth_storage.dart';
import 'features/home/user_profile.dart';
import 'features/notifications/notification_model.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/onboarding_storage.dart';
import 'features/settings/settings_state.dart';
import 'features/shell/main_shell.dart';
import 'features/splash/animated_splash_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  userProfileNotifier.value = UserProfile(
    name: 'Odiljon Sanoyev',
    phone: '+998 90 123 45 67',
    avatarPath: 'assets/images/auth/user.png',
    dateOfBirth: DateTime(1995, 6, 14),
    gender: Gender.male,
  );
  notificationUnreadNotifier.value = unreadNotificationCount();
  runApp(const KadastrApp());
}

class KadastrApp extends StatelessWidget {
  const KadastrApp({
    super.key,
    this.onboardingStorage = const OnboardingStorage(),
    this.authStorage = const AuthStorage(),
  });

  final OnboardingStorage onboardingStorage;
  final AuthStorage authStorage;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: localeNotifier,
          builder: (context, locale, _) {
            return MaterialApp(
              title: 'Kadastr',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeMode,
              builder: _systemUiBuilder,
              home: _AppRoot(
                onboardingStorage: onboardingStorage,
                authStorage: authStorage,
                locale: locale,
              ),
            );
          },
        );
      },
    );
  }

  Widget _systemUiBuilder(BuildContext context, Widget? child) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = isDark
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light, // Android: white
            statusBarBrightness: Brightness.dark, // iOS: white
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark, // Android: dark
            statusBarBrightness: Brightness.light, // iOS: dark
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: child ?? const SizedBox.shrink(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot({
    required this.onboardingStorage,
    required this.authStorage,
    required this.locale,
  });

  final OnboardingStorage onboardingStorage;
  final AuthStorage authStorage;
  final Locale locale;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

enum _Stage { splash, onboarding, home }

class _AppRootState extends State<_AppRoot> {
  _Stage _stage = _Stage.splash;
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  Future<void> _bootstrap() async {
    final done = await widget.onboardingStorage.hasCompleted();
    if (!mounted) return;
    setState(() => _onboardingDone = done);
  }

  void _handleSplashComplete() {
    if (!mounted) return;
    setState(() {
      _stage = (_onboardingDone ?? false) ? _Stage.home : _Stage.onboarding;
    });
  }

  Future<void> _handleOnboardingFinished() async {
    await widget.onboardingStorage.markCompleted();
    if (!mounted) return;
    setState(() => _stage = _Stage.home);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: switch (_stage) {
        _Stage.splash => Container(
          key: const ValueKey('splash'),
          color: AppColors.splashGreen,
          child: AnimatedSplashScreen(onComplete: _handleSplashComplete),
        ),
        _Stage.onboarding => OnboardingScreen(
          key: const ValueKey('onboarding'),
          onFinished: _handleOnboardingFinished,
        ),
        _Stage.home => MainShell(
          key: const ValueKey('home'),
          authStorage: widget.authStorage,
          locale: widget.locale,
        ),
      },
    );
  }
}
