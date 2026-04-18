import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/onboarding_storage.dart';
import 'features/splash/animated_splash_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  runApp(const KadastrApp());
}

class KadastrApp extends StatelessWidget {
  const KadastrApp({
    super.key,
    this.onboardingStorage = const OnboardingStorage(),
  });

  final OnboardingStorage onboardingStorage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kadastr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: _AppRoot(onboardingStorage: onboardingStorage),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot({required this.onboardingStorage});

  final OnboardingStorage onboardingStorage;

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
    _loadOnboardingFlag();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      );
    });
  }

  Future<void> _loadOnboardingFlag() async {
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
        _Stage.home => const HomeScreen(key: ValueKey('home')),
      },
    );
  }
}
