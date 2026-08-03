import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/pressable_scale.dart';
import '../models/service_item.dart';

/// A dark halo behind the card copy so the title/subtitle stay legible even
/// where a line passes over the bright 3D logo. Three stacked shadows: a solid
/// black core hugging the glyphs (kills contrast against light art), plus two
/// progressively wider, softer fall-offs so the halo reads as a glow of depth
/// rather than a hard outline. Strong on purpose — it has to hold up over the
/// brightest part of the logo.
const List<Shadow> _textShadows = [
  Shadow(color: Color(0xFF000000), blurRadius: 6),
  Shadow(color: Color(0xCC000000), blurRadius: 14),
  Shadow(color: Color(0x99000000), blurRadius: 22),
];

class ServiceCard extends StatefulWidget {
  const ServiceCard({super.key, required this.item, required this.onTap});

  final ServiceItem item;
  final VoidCallback onTap;

  @override
  State<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<ServiceCard>
    with SingleTickerProviderStateMixin {
  // Subtle press-bounce on the card's logo: dip in, overshoot, settle. We let it
  // finish before navigating so the tap feels acknowledged (a beat, not a lag).
  //
  // Shortened from 300ms, which had crossed from beat into lag: with the ~300ms
  // route transition queued behind it a tap cost ~600ms before the next screen
  // was on its way, and a profile trace showed the app producing NO frames at
  // all for ~340ms after a tap — it was parked on this controller. 150ms still
  // reads as a distinct jump without outstaying it.
  static const Duration _bounceDuration = Duration(milliseconds: 150);

  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: _bounceDuration,
  );
  late final Animation<double> _logoScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.84).chain(CurveTween(curve: Curves.easeOut)),
      weight: 38,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.84, end: 1.06).chain(CurveTween(curve: Curves.easeOut)),
      weight: 34,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
      weight: 28,
    ),
  ]).animate(_bounce);

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_bounce.isAnimating) return; // ignore double-taps mid-bounce
    HapticFeedback.mediumImpact();
    await _bounce.forward(from: 0);
    if (!mounted) return;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isWide = item.layout == ServiceLayout.wide;
    final radius = BorderRadius.circular(24);

    return PressableScale(
      child: Material(
        color: const Color(0xFF0E1213),
        clipBehavior: Clip.antiAlias,
        // Soft accent-tinted rim + a colored drop shadow so the card lifts off
        // the light background and reads as a premium, tactile surface.
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: item.accent.withValues(alpha: 0.20), width: 1),
        ),
        elevation: 10,
        shadowColor: item.accent.withValues(alpha: 0.30),
        child: InkWell(
          onTap: _handleTap,
          child: Stack(
            children: [
              // Accent glow — anchored to the SAME corner as the 3D image
              // (bottom-right) so the object appears to emit its colour.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: isWide
                          ? const Alignment(0.72, 1.05)
                          : const Alignment(0.55, 1.15),
                      radius: isWide ? 0.95 : 1.25,
                      colors: [
                        item.accent.withValues(alpha: 0.55),
                        item.accent.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              // Subtle top sheen — a faint light fall-off from the top edge for
              // a glossy, premium finish (top-light + bottom-accent depth).
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.white.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 3D object — anchored firmly to the bottom-right corner, sized
              // to be a hero element that bleeds slightly off the edge.
              Positioned(
                right: isWide ? -4 : -8,
                bottom: isWide ? -6 : -12,
                child: ScaleTransition(
                  scale: _logoScale,
                  // Boundary inside the transition, around the thing being
                  // scaled, so the bounce doesn't drag the card's gradients,
                  // shadow and blurred text into a repaint with it.
                  child: RepaintBoundary(
                    child: Image.asset(
                      item.asset,
                      height: isWide ? 148 : 142,
                      fit: BoxFit.fitHeight,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        height: 1.2,
                        letterSpacing: -0.2,
                        color: Colors.white,
                        shadows: _textShadows,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Keep the copy on the left so it never collides with the
                    // 3D object in the bottom-right.
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: isWide ? 0.62 : 0.9,
                      child: Text(
                        item.subtitle,
                        style: const TextStyle(
                          fontFamily: 'MTSText',
                          fontWeight: FontWeight.w400,
                          fontSize: 11.5,
                          height: 1.35,
                          color: Color(0xFFB7BDC2),
                          shadows: _textShadows,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
