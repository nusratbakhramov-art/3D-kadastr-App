import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'features/auth/auth_storage.dart';
import 'features/home/user_profile.dart';
import 'features/notifications/notification_model.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/onboarding_storage.dart';
import 'features/market/data/market_regions_store.dart';
import 'features/services/data/calculator_pricing_store.dart';
import 'features/settings/locale_storage.dart';
import 'features/settings/settings_state.dart';
import 'features/shell/main_shell.dart';
import 'features/splash/animated_splash_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  // Faqat portret rejim — ilova hech qachon yon (landscape) aylanmaydi.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Foydalanuvchi profili AuthStorage'dan KadastrApp.initState ichida
  // yuklanadi (saqlangan sessiya bo'lsa). Mehmon (login qilmagan) holatda
  // userProfileNotifier null bo'lib qoladi va Profil ekranida "Kirish" tugmasi
  // ko'rinadi.
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
              locale: locale,
              supportedLocales: const [
                Locale('uz'),
                Locale('ru'),
                Locale('en'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null) return;

        final focusContext = focus.context;
        if (focusContext != null) {
          final renderObject = focusContext.findRenderObject();
          if (renderObject is RenderBox) {
            final local = renderObject.globalToLocal(event.position);
            final isInsideFocusedField =
                local.dx >= 0 &&
                local.dy >= 0 &&
                local.dx <= renderObject.size.width &&
                local.dy <= renderObject.size.height;
            if (isInsideFocusedField) return;
          }
        }

        focus.unfocus();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: child ?? const SizedBox.shrink(),
      ),
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
    // Kalkulyator narxlarini keshdan darhol o'qib, fonda backend'dan
    // yangilaymiz. Fire-and-forget — splash/bootstrap vaqtiga ta'sir qilmaydi
    // (notifier boshlang'ich qiymati = defaults, offline xavfsiz).
    unawaited(CalculatorPricingStore.instance.loadCachedThenRefresh());

    // Market filtridagi tumanlar ro'yxati ham admin paneldan keladi — keshdan
    // o'qib, fonda yangilaymiz (offline xavfsiz, default = kMarketDistricts).
    unawaited(MarketRegionsStore.instance.loadCachedThenRefresh());

    // Avval saqlangan locale ni yuklab, app bo'ylab qo'llaymiz. Bu
    // localeNotifier'ni o'zgartiradi va MaterialApp rebuild bo'lib, butun
    // widget tree yangi til bilan tarjima qilinadi.
    final savedLocale = await const LocaleStorage().load();
    if (savedLocale != null) {
      // Foydalanuvchi tilni qo'lda tanlagan — o'shanga rioya qilamiz.
      if (savedLocale != localeNotifier.value) {
        localeNotifier.value = savedLocale;
      }
    } else {
      // Foydalanuvchi tanlamagan — QURILMA tilini kuzatamiz (App Store 2.1(a):
      // qurilma ruscha bo'lsa, ilova ham ruscha ochilsin). Qo'llab-quvvatlanadigan
      // til (uz/ru/en) bo'lsa o'sha, aks holda default uz.
      final deviceLang =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      const supported = {'uz', 'ru', 'en'};
      final resolved = supported.contains(deviceLang)
          ? Locale(deviceLang)
          : const Locale('uz');
      if (resolved != localeNotifier.value) {
        localeNotifier.value = resolved;
      }
    }

    final done = await widget.onboardingStorage.hasCompleted();
    final profile = await widget.authStorage.loadProfile();
    final session = await widget.authStorage.loadSession();
    final phone = session.phone == null ? null : '+${session.phone}';
    if (profile.fullName.isNotEmpty) {
      userProfileNotifier.value = UserProfile(
        name: profile.fullName,
        phone: phone,
        dateOfBirth: profile.dateOfBirth,
        gender: profile.gender,
      );
    }
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
