import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/pressable_scale.dart';
import '../models/service_item.dart';

class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.item, required this.onTap});

  final ServiceItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
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
                child: Image.asset(
                  item.asset,
                  height: isWide ? 188 : 142,
                  fit: BoxFit.fitHeight,
                  filterQuality: FilterQuality.medium,
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
                        maxLines: isWide ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'MTSText',
                          fontWeight: FontWeight.w400,
                          fontSize: 12.5,
                          height: 1.4,
                          color: Color(0xFFB7BDC2),
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
