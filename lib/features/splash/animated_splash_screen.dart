import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_colors.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  static const double _logoStartScale = 1.55;
  static const double _logoEndScale = 0.72;
  static const double _logoStartTiltDeg = 15;
  static const double _logoEndOffsetX = -98;
  static const double _textStartOffsetX = 0;
  static const double _textEndOffsetX = 52;
  static const double _logoSizePx = 140;
  static const double _textFontSize = 32;

  static const Cubic _emphasizedMove = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Cubic _settleCurve = Cubic(0.65, 0.0, 0.35, 1.0);
  static const Cubic _gentleOvershoot = Cubic(0.34, 1.12, 0.64, 1.0);
  static const Cubic _crispOut = Cubic(0.16, 1.0, 0.3, 1.0);

  late final AnimationController _controller;
  late final Animation<double> _rotationT;
  late final Animation<double> _scaleT;
  late final Animation<double> _logoSlideT;
  late final Animation<double> _textSlideT;
  late final Animation<double> _textOpacityT;
  late final Animation<double> _textScaleT;

  bool _completed = false;

  @override
  void initState() {
    super.initState();
    // Timeline (2800ms total):
    //   0 –  900ms  HOLD    logo big + tilted 15°, dead-center
    // 900 – 1600ms  SETTLE  logo rotates 15°→0° and shrinks, stays centered
    //1600 – 2500ms  REVEAL  logo slides left; text extrudes from under it and slides right
    //2500 – 2800ms  DWELL   locked-up final frame before handoff
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _rotationT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.321, 0.571, curve: _settleCurve),
    );

    _scaleT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.321, 0.571, curve: _settleCurve),
    );

    _logoSlideT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.571, 0.893, curve: _emphasizedMove),
    );

    _textSlideT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.60, 0.893, curve: _gentleOvershoot),
    );

    _textOpacityT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.62, 0.85, curve: Curves.easeOutQuart),
    );

    _textScaleT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.60, 0.88, curve: _crispOut),
    );

    _controller.addStatusListener(_handleStatus);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_completed) {
      _completed = true;
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) widget.onComplete();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashGreen,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final scale = lerpDouble(
              _logoStartScale,
              _logoEndScale,
              _scaleT.value,
            )!;
            final tilt = lerpDouble(
              _logoStartTiltDeg * math.pi / 180,
              0,
              _rotationT.value,
            )!;
            final logoDx = lerpDouble(
              0.0,
              _logoEndOffsetX,
              _logoSlideT.value,
            )!;
            final textDx = lerpDouble(
              _textStartOffsetX,
              _textEndOffsetX,
              _textSlideT.value,
            )!;
            final textScale = lerpDouble(0.88, 1.0, _textScaleT.value)!;
            final textOpacity = _textOpacityT.value.clamp(0.0, 1.0);

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
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
                Transform.translate(
                  offset: Offset(logoDx, 0),
                  child: Transform.rotate(
                    angle: tilt,
                    child: Transform.scale(
                      scale: scale,
                      child: SvgPicture.asset(
                        'assets/branding/splash-logo.svg',
                        width: _logoSizePx,
                        height: _logoSizePx,
                        semanticsLabel: 'Kadastr',
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrandText extends StatelessWidget {
  const _BrandText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '3D kadastr',
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w900,
        fontSize: _AnimatedSplashScreenState._textFontSize,
        color: Color(0xFF011606),
        letterSpacing: -0.5,
      ),
    );
  }
}
