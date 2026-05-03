import 'package:flutter/material.dart';

/// Soft mint radial glow rendered behind a screen's content. Drop into the
/// first slot of a [Stack] with [StackFit.expand]. In dark mode the glow
/// switches to a deeper, low-alpha green so it doesn't wash out the page.
class AppGlowBackground extends StatelessWidget {
  const AppGlowBackground({
    super.key,
    this.primary,
    this.secondary,
  });

  final Color? primary;
  final Color? secondary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedPrimary = primary ?? (isDark
        ? const Color(0x330A6B23)
        : const Color(0x66B8F0CC));
    final resolvedSecondary = secondary ?? (isDark
        ? const Color(0x22034112)
        : const Color(0x40D6F8E2));
    final primaryFade = resolvedPrimary.withValues(alpha: 0);
    final secondaryFade = resolvedSecondary.withValues(alpha: 0);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: -w * 0.5,
                  top: -h * 0.22,
                  width: w * 1.2,
                  height: h * 0.45,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.5,
                        colors: [resolvedPrimary, primaryFade],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -w * 0.45,
                  top: -h * 0.12,
                  width: w * 0.85,
                  height: h * 0.32,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.5,
                        colors: [resolvedSecondary, secondaryFade],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
