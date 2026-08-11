import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;

import '../../theme/app_colors.dart';

/// Splash — oldindan render qilingan 3D logo kadrlari (webp, shaffof):
///   1) logo pastdan markazga ko'tariladi va YON → YUZ ga buriladi (frame 0→35)
///   2) markazda yuzi bilan turadi (DWELL)
///   3) chapga suriladi, "3D kadastr" matni o'ngdan chiqadi (REVEAL)
/// Kadrlar `dart:ui` bilan bir marta `ui.Image` ga dekod qilinib, `RawImage`
/// orqali chiziladi — kesh qidiruvi/qayta-dekod yo'q, silliq o'ynaydi.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  // DEBUG: splashni tekshirish uchun — true bo'lsa animatsiya tugagach uyga
  // o'tmasdan qayta-qayta o'ynaydi. Yakunda `false` ga qaytar.
  static const bool _loopForTesting = false;

  static const int _frameCount = 90; // loopable 360° aylanish, ~4°/kadr (silliq)
  static const int _spinTurns = 1;   // ko'tarilishda bitta to'liq 360° aylanish
  static const int _decodeWidth = 700; // manba 780px; katta logo uchun tiniqroq
  static const double _logoBox = 264;
  static const double _textFontSize = 46;
  static const double _logoRiseFromY = 300; // pastdan shu balandlikda paydo
  static const double _logoEndOffsetX = -118; // REVEAL: chapga (logo bilan matn orasida masofa)
  static const double _textStartOffsetX = 0;
  static const double _textEndOffsetX = 72; // REVEAL: o'ngga

  static const Cubic _emphasizedMove = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Cubic _crispOut = Cubic(0.16, 1.0, 0.3, 1.0);

  // The upward MOVE springs — rises to the top with a soft overshoot, then
  // settles. Rotation + scale ride this SAME value (clamped) in build(), so they
  // finish exactly as the logo first reaches the top and never spin in place.
  // The wordmark keeps its own snappier spring.
  final Curve _riseSpring = const _OvershootCurve(1.0);
  final Curve _textSpring = const _OvershootCurve(1.6);

  late final AnimationController _controller;
  late final Animation<double> _riseT;
  late final Animation<double> _logoSlideT;
  late final Animation<double> _textSlideT;
  late final Animation<double> _textOpacityT;
  late final Animation<double> _textScaleT;

  List<ui.Image> _frames = const [];
  bool _completed = false;
  bool _started = false;

  // Haptics land on the two moments the animation *arrives* somewhere, not on
  // the motion itself — buzzing through a move feels like a rattle, a tap at
  // the end of one feels like weight. Flags because the tick fires every frame.
  // Two beats only — restraint reads cleaner than a sequence and survives cheap
  // Android motors: a MEDIUM tap when the logo lands at the top, then a LIGHT
  // tap as the wordmark appears. Fired in order, once each, reset on loop.
  static const List<double> _hapticTimes = [
    0.24, // landed at the top (medium)
    0.52, // wordmark appears (light)
  ];
  int _hapticI = 0;

  static String _framePath(int i) =>
      'assets/branding/logo-frames/frame_${i.toString().padLeft(3, '0')}.webp';

  @override
  void initState() {
    super.initState();
    // Timeline (3800ms):
    //   0 –1520ms  RISE+SPIN  pastdan markazga + yon→yuz (frame 0→35)
    //1520 –2450ms  DWELL      markazda yuzi bilan turadi
    //2450 –3460ms  REVEAL     chapga suriladi; matn o'ngdan chiqadi
    //3460 –3800ms  SETTLE
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    // The upward move springs (soft overshoot at the top, then settle). Rotation
    // and scale are derived from this SAME value (clamped) in build(), so they
    // finish exactly as the logo first reaches the top — never spinning in place.
    _riseT = CurvedAnimation(
      parent: _controller,
      curve: Interval(0.0, 0.42, curve: _riseSpring),
    );
    // Reveal starts the instant the rise lands (0.42) — no dead dwell.
    _logoSlideT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.42, 0.72, curve: _emphasizedMove),
    );
    _textSlideT = CurvedAnimation(
      parent: _controller,
      curve: Interval(0.45, 0.80, curve: _textSpring),
    );
    _textOpacityT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.48, 0.66, curve: Curves.easeOutQuart),
    );
    _textScaleT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.76, curve: _crispOut),
    );
    _controller.addStatusListener(_handleStatus);
    _controller.addListener(_handleHaptics);
    _loadFramesAndStart();
  }

  /// Fires each beat once as the controller passes it.
  ///
  /// Driven off controller *value* rather than timers so it can never drift
  /// from the visuals: the animation only starts once 36 frames have decoded,
  /// and a timer scheduled in initState would run against a logo still waiting
  /// to appear.
  void _handleHaptics() {
    final v = _controller.value;
    while (_hapticI < _hapticTimes.length && v >= _hapticTimes[_hapticI]) {
      switch (_hapticI) {
        case 0: // logo lands at the top
          HapticFeedback.mediumImpact();
          break;
        case 1: // wordmark appears
          HapticFeedback.lightImpact();
          break;
      }
      _hapticI++;
    }
  }

  Future<void> _loadFramesAndStart() async {
    if (_started) return;
    _started = true;
    try {
      _frames = await Future.wait([
        for (int i = 0; i < _frameCount; i++) _decodeFrame(i),
      ]);
    } catch (_) {}
    if (!mounted) return;
    setState(() {}); // kadrlar tayyor
    _controller.forward();
  }

  Future<ui.Image> _decodeFrame(int i) async {
    final data = await rootBundle.load(_framePath(i));
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: _decodeWidth,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_loopForTesting) {
      // Yakuniy holatni bir lahza ko'rsatib, keyin boshidan qayta o'ynaymiz.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _hapticI = 0;
        _controller
          ..reset()
          ..forward();
      });
      return;
    }
    if (!_completed) {
      _completed = true;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) widget.onComplete();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.removeListener(_handleHaptics);
    _controller.dispose();
    for (final img in _frames) {
      img.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Responsive scale: the lockup is designed for a ~440pt-wide screen (Pro Max).
    // On narrower phones everything scales down so the logo + wordmark still fit.
    final screenW = MediaQuery.of(context).size.width;
    final scale = (screenW / 440.0).clamp(0.6, 1.05);
    final logoBox = _logoBox * scale;
    final logoEndX = _logoEndOffsetX * scale;
    final textEndX = _textEndOffsetX * scale;
    final riseFromY = _logoRiseFromY * scale;
    final fontSize = _textFontSize * scale;
    return Scaffold(
      backgroundColor: AppColors.splashGreen,
      body: Stack(
        children: [
          const Positioned.fill(child: _SplashPatternBackground()),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final riseDy = ui.lerpDouble(
                  riseFromY,
                  0.0,
                  _riseT.value,
                )!;
                // Rotation + scale ride the rise value CLAMPED to [0,1] so they
                // complete the instant the logo first reaches the top and then
                // hold through the spring's post-arrival bounce (position only).
                final spinProg = _riseT.value.clamp(0.0, 1.0).toDouble();
                final logoScale = ui.lerpDouble(0.6, 1.0, spinProg)!;
                // Loopable 360° frames: _spinTurns full turn(s) across the
                // ascent, landing on frame 0 (rest pose) at arrival.
                final frameIdx = _frames.isEmpty
                    ? 0
                    : (spinProg * _frames.length * _spinTurns).round() %
                        _frames.length;
                final logoDx = ui.lerpDouble(
                  0.0,
                  logoEndX,
                  _logoSlideT.value,
                )!;
                final textDx = ui.lerpDouble(
                  _textStartOffsetX,
                  textEndX,
                  _textSlideT.value,
                )!;
                final textOpacity = _textOpacityT.value.clamp(0.0, 1.0);
                final textScale =
                    ui.lerpDouble(0.88, 1.0, _textScaleT.value)!;
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Matn — logo ostidan chiqib o'ngga suriladi.
                    Transform.translate(
                      offset: Offset(textDx, 0),
                      child: Opacity(
                        opacity: textOpacity,
                        child: Transform.scale(
                          scale: textScale,
                          alignment: Alignment.centerLeft,
                          child: _BrandText(fontSize: fontSize),
                        ),
                      ),
                    ),
                    // 3D logo kadri — pastdan ko'tariladi, yon→yuz, keyin chapga.
                    Transform.translate(
                      offset: Offset(logoDx, riseDy),
                      child: Transform.scale(
                        scale: logoScale,
                        child: SizedBox(
                          width: logoBox,
                          height: logoBox,
                          child: _frames.isEmpty
                              ? const SizedBox.shrink()
                              : RawImage(
                                  image: _frames[frameIdx],
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashPatternBackground extends StatelessWidget {
  const _SplashPatternBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final patternSize = constraints.maxWidth;
          return Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                width: patternSize,
                height: patternSize,
                child: Image.asset(
                  'assets/branding/splash/pattern-tr.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.topRight,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                width: patternSize,
                height: patternSize,
                child: Image.asset(
                  'assets/branding/splash/pattern-bl.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomLeft,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BrandText extends StatelessWidget {
  const _BrandText({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Brand wordmark — intentionally NOT backend-driven. The splash paints the
    // very first frame, before the i18n bundle finishes loading, so a tr() key
    // would flash raw. It's a fixed brand mark anyway.
    return Text(
      '3D kadastr',
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        color: const Color(0xFF011606),
        letterSpacing: -0.5,
      ),
    );
  }
}

/// A "back-out" overshoot curve (like [Curves.easeOutBack] but with a tunable
/// [tension]): eases toward the target, overshoots past it, then settles back to
/// EXACTLY 1 at t == 1. Crucially it ARRIVES at the end of its interval — no
/// early float — so nothing hangs waiting before the next beat. Values exceed 1
/// mid-way (that overshoot IS the spring). Higher [tension] = a bigger pop.
class _OvershootCurve extends Curve {
  const _OvershootCurve(this.tension);

  final double tension;

  @override
  double transformInternal(double t) {
    t -= 1.0;
    return t * t * ((tension + 1) * t + tension) + 1;
  }
}
