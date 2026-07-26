/// Gradient-glass material for pressable surfaces.
///
/// The home call/chat FABs and the carousel's open-listing chip both use it, on
/// purpose: they sit on the same screen — the FABs float directly over the
/// carousel — and when each grew its own look the result read as three
/// different apps stacked on one page. One recipe, one family, so a tweak here
/// keeps them in step instead of drifting apart again.
///
/// Not a flat fill: a solid swatch is exactly what made these look cheap. The
/// body runs light→deep so it catches light at the top, a white sheen glazes
/// the upper half, a hairline rim picks out the edge, and a hue-matched bloom
/// grounds it against the feed.
library;

import 'package:flutter/material.dart';

class GradientSurface extends StatelessWidget {
  const GradientSurface({
    super.key,
    required this.light,
    required this.base,
    required this.deep,
    required this.size,
    required this.radius,
    required this.child,
    this.onTap,
  });

  /// Top of the fill.
  final Color light;

  /// Mid-stop, and the hue the bloom is tinted with.
  final Color base;

  /// Bottom of the fill.
  final Color deep;

  final double size;
  final double radius;

  /// Centred content — usually an icon, tinted white by the caller.
  final Widget child;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);

    return DecoratedBox(
      // Outside the clip — a shadow drawn inside would be clipped away.
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          // Soft neutral drop shadow — grounded BELOW the orb, pulled in with a
          // negative spread so it doesn't smear into a halo around the edges.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: size * 0.16,
            spreadRadius: -size * 0.06,
            offset: Offset(0, size * 0.11),
          ),
          // Faint hue tint just under the base, kept tight — a hint of grounding
          // colour, not the wide glow it used to throw.
          BoxShadow(
            color: base.withValues(alpha: 0.18),
            blurRadius: size * 0.14,
            spreadRadius: -size * 0.11,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            // 1. The body: light at the top edge, deep at the bottom.
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [light, base, deep],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
            // 2. Lower-hemisphere shading — a little depth toward the base,
            //    kept light so the sphere doesn't dissolve into a dark feed.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.14),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
            // 3. Broad glass sheen over the upper half.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: size * 0.55,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.34),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // 4. Specular hotspot near the top — the bright wet-gloss highlight
            //    that sells the 3D glass-orb look of the reference icons.
            Positioned(
              top: size * 0.06,
              left: size * 0.2,
              right: size * 0.2,
              height: size * 0.42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.25),
                    radius: 0.85,
                    colors: [
                      Colors.white.withValues(alpha: 0.80),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // 5. Rim: brighter now so the edge stays crisp against a dark
            //    background instead of dissolving into it.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: r,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.32),
                    width: 1.0,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, child: Center(child: child)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
