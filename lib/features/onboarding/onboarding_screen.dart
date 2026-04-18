import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'onboarding_page_data.dart';
import 'widgets/language_selector.dart';
import 'widgets/onboarding_background.dart';
import 'widgets/onboarding_nav_button.dart';
import 'widgets/skip_button.dart';
import 'widgets/story_progress_bar.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.initialLocale = AppLocale.uz,
    this.segmentDuration = const Duration(seconds: 5),
  });

  final VoidCallback onFinished;
  final Locale initialLocale;
  final Duration segmentDuration;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.segmentDuration,
  );

  int _index = 0;
  late Locale _locale = widget.initialLocale;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener(_onProgressStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _progress.forward();
    });
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _index < onboardingPages.length - 1) {
      _goToPage(_index + 1);
    }
  }

  void _goToPage(int index) {
    setState(() => _index = index);
    _progress
      ..reset()
      ..forward();
  }

  void _onContinue() {
    if (_index < onboardingPages.length - 1) {
      _goToPage(_index + 1);
    } else {
      widget.onFinished();
    }
  }

  void _rewind() {
    if (_index == 0) return;
    _goToPage(_index - 1);
  }

  void _pauseHold(PointerDownEvent _) {
    if (_progress.isAnimating) {
      _paused = true;
      _progress.stop();
    }
  }

  void _resumeHold([PointerEvent? _]) {
    if (_paused) {
      _paused = false;
      _progress.forward();
    }
  }

  @override
  void dispose() {
    _progress.removeStatusListener(_onProgressStatus);
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = onboardingPages[_index];
    final isFirst = _index == 0;

    return Scaffold(
      backgroundColor: AppColors.greenBlack,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _pauseHold,
        onPointerUp: _resumeHold,
        onPointerCancel: _resumeHold,
        child: OnboardingBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                children: [
                  StoryProgressBar(
                    count: onboardingPages.length,
                    currentIndex: _index,
                    progress: _progress,
                    height: 4,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 36,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        LanguageSelector(
                          current: _locale,
                          onChanged: (l) => setState(() => _locale = l),
                        ),
                        const Spacer(),
                        SkipButton(
                          label: AppLocale.skipLabel(_locale),
                          onPressed: widget.onFinished,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1200 / (2480 * 0.78),
                        child: ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Color(0x00FFFFFF),
                            ],
                            stops: [0.0, 0.78, 1.0],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: Image.asset(
                            page.mockupAsset,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 116,
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 36,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Text(
                              page.title(_locale),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.visible,
                              style: const TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 26,
                                height: 1.3,
                                color: AppColors.textBlack,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Text(
                              page.description(_locale),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.visible,
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w400,
                                fontSize: 16,
                                height: 1.3,
                                color: AppColors.textBlack.withValues(
                                  alpha: 0.78,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _NavRow(
                    showBack: !isFirst,
                    continueLabel: AppLocale.continueLabel(_locale),
                    backLabel: AppLocale.backLabel(_locale),
                    onContinue: _onContinue,
                    onBack: _rewind,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.showBack,
    required this.continueLabel,
    required this.backLabel,
    required this.onContinue,
    required this.onBack,
  });

  final bool showBack;
  final String continueLabel;
  final String backLabel;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    if (!showBack) {
      return SizedBox(
        width: double.infinity,
        child: OnboardingNavButton(
          label: continueLabel,
          variant: OnboardingNavVariant.primary,
          onPressed: onContinue,
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OnboardingNavButton(
            label: backLabel,
            variant: OnboardingNavVariant.secondary,
            onPressed: onBack,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OnboardingNavButton(
            label: continueLabel,
            variant: OnboardingNavVariant.primary,
            onPressed: onContinue,
          ),
        ),
      ],
    );
  }
}
