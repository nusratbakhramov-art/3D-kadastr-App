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
  static const int _frameCount = 36;
  static const int _decodeWidth = 420; // retina (~176px ekran)
  static const double _logoBox = 176;
  static const double _textFontSize = 30;
  static const double _logoRiseFromY = 300; // pastdan shu balandlikda paydo
  static const double _logoEndOffsetX = -82; // REVEAL: chapga
  static const double _textStartOffsetX = 0;
  static const double _textEndOffsetX = 74; // REVEAL: o'ngga (+12px nudge)

  static const Cubic _riseCurve = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Cubic _emphasizedMove = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Cubic _gentleOvershoot = Cubic(0.34, 1.12, 0.64, 1.0);
  static const Cubic _crispOut = Cubic(0.16, 1.0, 0.3, 1.0);

  late final AnimationController _controller;
  late final Animation<double> _riseT;
  late final Animation<double> _spinT;
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
  static const double _tLanded = 0.40; // rise+spin ends: the logo touches down
  static const double _tRevealed = 0.675; // the wordmark springs in
  bool _hapticLanded = false;
  bool _hapticRevealed = false;

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
      duration: const Duration(milliseconds: 3800),
    );
    _riseT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.40, curve: _riseCurve),
    );
    _spinT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.40, curve: Curves.easeInOut),
    );
    _logoSlideT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.645, 0.91, curve: _emphasizedMove),
    );
    _textSlideT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.675, 0.91, curve: _gentleOvershoot),
    );
    _textOpacityT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.70, 0.88, curve: Curves.easeOutQuart),
    );
    _textScaleT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.675, 0.90, curve: _crispOut),
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
    if (!_hapticLanded && v >= _tLanded) {
      _hapticLanded = true;
      HapticFeedback.mediumImpact();
    }
    if (!_hapticRevealed && v >= _tRevealed) {
      _hapticRevealed = true;
      HapticFeedback.lightImpact();
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
    if (status == AnimationStatus.completed && !_completed) {
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
                  _logoRiseFromY,
                  0.0,
                  _riseT.value,
                )!;
                final frameIdx = _frames.isEmpty
                    ? 0
                    : (_spinT.value * (_frameCount - 1))
                        .round()
                        .clamp(0, _frameCount - 1);
                final logoDx = ui.lerpDouble(
                  0.0,
                  _logoEndOffsetX,
                  _logoSlideT.value,
                )!;
                final textDx = ui.lerpDouble(
                  _textStartOffsetX,
                  _textEndOffsetX,
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
                          child: const _BrandText(),
                        ),
                      ),
                    ),
                    // 3D logo kadri — pastdan ko'tariladi, yon→yuz, keyin chapga.
                    Transform.translate(
                      offset: Offset(logoDx, riseDy),
                      child: SizedBox(
                        width: _logoBox,
                        height: _logoBox,
                        child: _frames.isEmpty
                            ? const SizedBox.shrink()
                            : RawImage(
                                image: _frames[frameIdx],
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
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
  const _BrandText();

  @override
  Widget build(BuildContext context) {
    // Brand wordmark — intentionally NOT backend-driven. The splash paints the
    // very first frame, before the i18n bundle finishes loading, so a tr() key
    // would flash raw. It's a fixed brand mark anyway.
    return Text(
      '3D kadastr',
      style: const TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w900,
        fontSize: _AnimatedSplashScreenState._textFontSize,
        color: Color(0xFF011606),
        letterSpacing: -0.5,
      ),
    );
  }
}
