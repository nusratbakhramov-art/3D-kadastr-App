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
    with TickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.segmentDuration,
  );
  late final AnimationController _textReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final AnimationController _pageTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1.0,
  );
  late final Animation<double> _titleReveal = CurvedAnimation(
    parent: _textReveal,
    curve: const Interval(0.0, 0.75, curve: Cubic(0.2, 0.8, 0.2, 1.0)),
  );
  late final Animation<double> _descReveal = CurvedAnimation(
    parent: _textReveal,
    curve: const Interval(0.18, 1.0, curve: Cubic(0.2, 0.8, 0.2, 1.0)),
  );

  int _index = 0;
  int? _prevIndex;
  bool _isForward = true;
  late Locale _locale = widget.initialLocale;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener(_onProgressStatus);
    _pageTransition.addStatusListener(_onPageTransitionStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _progress.forward();
        _textReveal.forward();
      }
    });
  }

  void _onPageTransitionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _prevIndex != null) {
      setState(() => _prevIndex = null);
    }
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _index < onboardingPages.length - 1) {
      _goToPage(_index + 1);
    }
  }

  void _goToPage(int index) {
    if (index == _index) return;
    setState(() {
      _prevIndex = _index;
      _isForward = index > _index;
      _index = index;
    });
    _progress
      ..reset()
      ..forward();
    _pageTransition
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
    _pageTransition.removeStatusListener(_onPageTransitionStatus);
    _progress.dispose();
    _textReveal.dispose();
    _pageTransition.dispose();
    super.dispose();
  }

  Widget _revealed({required Animation<double> anim, required Widget child}) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, c) {
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, (1 - anim.value) * 8),
            child: c,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildTitle(OnboardingPageData page) {
    return _revealed(
      anim: _titleReveal,
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
    );
  }

  Widget _buildDescription(OnboardingPageData page) {
    return _revealed(
      anim: _descReveal,
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
          color: AppColors.textBlack.withValues(alpha: 0.78),
        ),
      ),
    );
  }

  Widget _buildNavRow(int idx) {
    final isFirst = idx == 0;
    return _NavRow(
      showBack: !isFirst,
      continueLabel: AppLocale.continueLabel(_locale),
      backLabel: AppLocale.backLabel(_locale),
      onContinue: _onContinue,
      onBack: _rewind,
    );
  }

  Widget _slideSwap({
    required Widget Function(int index) builder,
    double begin = 0.0,
    double end = 1.0,
  }) {
    return AnimatedBuilder(
      animation: _pageTransition,
      builder: (context, _) {
        final raw = _pageTransition.value;
        if (_prevIndex == null || raw >= 1.0) return builder(_index);
        final span = end - begin;
        final t = ((raw - begin) / span).clamp(0.0, 1.0);
        final v = const Cubic(0.2, 0.8, 0.2, 1.0).transform(t);
        const dist = 16.0;
        final dir = _isForward ? 1.0 : -1.0;
        return Stack(
          alignment: Alignment.topCenter,
          fit: StackFit.passthrough,
          children: [
            IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: 1 - v,
                child: Transform.translate(
                  offset: Offset(-dir * v * dist, 0),
                  child: builder(_prevIndex!),
                ),
              ),
            ),
            Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(dir * (1 - v) * dist, 0),
                child: builder(_index),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                            onboardingPages[_index].mockupAsset,
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
                            child: _slideSwap(
                              begin: 0.0,
                              end: 0.65,
                              builder: (idx) =>
                                  _buildTitle(onboardingPages[idx]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: _slideSwap(
                              begin: 0.15,
                              end: 0.80,
                              builder: (idx) =>
                                  _buildDescription(onboardingPages[idx]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _slideSwap(
                    begin: 0.30,
                    end: 1.0,
                    builder: (idx) => _buildNavRow(idx),
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
    super.key,
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
