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
          // Colour-matched bloom: the surface looks like it emits its own hue.
          // Scaled off `size` so a 28dp chip gets a chip-sized glow instead of
          // a 56dp button's halo smeared under it.
          BoxShadow(
            color: base.withValues(alpha: 0.45),
            blurRadius: size * 0.32,
            spreadRadius: -2,
            offset: Offset(0, size * 0.107),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.054),
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
            // 2. Glass sheen over the upper half only — the highlight that
            //    sells it as a rounded object rather than a printed square.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: size * 0.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.30),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // 3. Hairline rim: catches light on top, darkens underneath. Stays
            //    0.8 at every size — a hairline that scales stops being one.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: r,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 0.8,
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
