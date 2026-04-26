import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_item.dart';

class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.item, required this.onTap});

  final ServiceItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isWide = item.layout == ServiceLayout.wide;
    final radius = BorderRadius.circular(24);

    return Material(
      color: const Color(0xFF0E1213),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: isWide
                        ? const Alignment(-0.45, 1.15)
                        : const Alignment(-0.15, 1.15),
                    radius: isWide ? 0.65 : 1.05,
                    colors: [
                      item.accent.withValues(alpha: 0.6),
                      item.accent.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              right: isWide ? -8 : -14,
              bottom: isWide ? -8 : -18,
              child: Image.asset(
                item.asset,
                height: isWide ? 150 : 130,
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
                      height: 1.25,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: isWide ? 220 : double.infinity,
                    child: Text(
                      item.subtitle,
                      maxLines: isWide ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFFC2C7CC),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
