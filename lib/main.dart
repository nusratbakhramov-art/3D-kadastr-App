import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/app_navigation.dart';
import 'core/payment_deep_links.dart';
import 'core/push_notifications.dart';
import 'features/auth/auth_http_client.dart';
import 'features/auth/auth_storage.dart';
import 'features/notifications/notifications_api.dart';
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
  // Ilova ikonkasидаги badge'ni o'qilmaganlar soni bilan doim sinxron tutamiz:
  // har o'zgarishда (bootstrap/resume/login/o'qish/push) badge yangilanadi,
  // hammasi o'qilganда (0) tozalanadi. (Backend push'да badge=1 yuboradi.)
  syncAppBadge(notificationUnreadNotifier.value);
  notificationUnreadNotifier.addListener(
    () => syncAppBadge(notificationUnreadNotifier.value),
  );
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
              navigatorKey: rootNavigatorKey,
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

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  _Stage _stage = _Stage.splash;
  bool? _onboardingDone;

  // Re-entrancy guard — parallel requests can all trip a failed refresh at once.
  bool _handlingExpiry = false;

  @override
  void initState() {
    super.initState();
    // Refresh ham muvaffaqiyatsiz bo'lganda (refresh token tugagan/yaroqsiz)
    // AuthHttpClient sessiyani tozalaydi va shu callback'ni chaqiradi — biz
    // foydalanuvchini Home'ga qaytarib, "qayta kiring" deb xabar beramiz.
    AuthHttpClient.onSessionExpired = _handleSessionExpired;
    _bootstrap();
    // iOS Universal Links — to'lovdan keyin /pay-return/{id} appni ochadi.
    PaymentDeepLinks.init();
    // FCM push xabarnomalar — Firebase init, ruxsat, token ro'yxati, tap
    // navigatsiyasi. Firebase sozlanmagan bo'lsa jim o'chadi (app'ga tegmaydi).
    unawaited(PushNotifications.init());
    // App fonдан qaytganda (Payme'dan) kutilayotgan to'lov holatini tekshiradi —
    // native Payme `c=` universal link'ni ochmaydi, shu fallback qoplaydi.
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  void dispose() {
    if (AuthHttpClient.onSessionExpired == _handleSessionExpired) {
      AuthHttpClient.onSessionExpired = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Sessiya tiklab bo'lmaydigan darajada tugaganda: mahalliy auth holatini
  /// tozalab (storage AuthHttpClient tomonidan allaqachon tozalangan), ochiq
  /// ekranlarni yopib, asosiy tab'ga qaytaramiz va foydalanuvchini ogohlantiramiz.
  void _handleSessionExpired() {
    if (_handlingExpiry) return;
    _handlingExpiry = true;
    userProfileNotifier.value = null;
    notificationUnreadNotifier.value = 0;
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    shellTabRequest.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        final l = Localizations.localeOf(ctx);
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          SnackBar(content: Text(_sessionExpiredMessage(l))),
        );
      }
      _handlingExpiry = false;
    });
  }

  static String _sessionExpiredMessage(Locale l) => switch (l.languageCode) {
        'ru' => 'Сессия истекла. Войдите снова.',
        'en' => 'Session expired. Please sign in again.',
        _ => 'Sessiya muddati tugadi. Iltimos, qayta kiring.',
      };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PaymentDeepLinks.onResumed();
      // Fonдан qaytganda bildirishnoma badge'ini yangilaymiz (push kelgan bo'lishi mumkin).
      unawaited(refreshNotifications());
    }
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
      // Foydalanuvchi hali til tanlamagan — default O'ZBEK (qurilma tilidan
      // qat'i nazar). Foydalanuvchi keyin Onboarding/Sozlamalardan o'zgartira oladi.
      if (localeNotifier.value != const Locale('uz')) {
        localeNotifier.value = const Locale('uz');
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
    // Login qilgan bo'lsa — bildirishnoma badge'ini backenddan to'ldiramiz.
    if (session.token != null) {
      unawaited(refreshNotifications());
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
