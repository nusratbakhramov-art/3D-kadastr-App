/// Xaritalar uchun umumiy zoom (+/−) tugmalari.
///
/// `flutter_map` MapController orqali kamerani bittaga yaqinlashtiradi/
/// uzoqlashtiradi. Barcha manzil tanlash ekranlarida bir xil ko'rinish uchun
/// shu bitta primitiv ishlatiladi. Odatda Stack ichida `Positioned` bilan
/// joylashtiriladi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../theme/app_colors.dart';

class MapZoomControls extends StatelessWidget {
  const MapZoomControls({
    super.key,
    required this.controller,
    this.minZoom = 4,
    this.maxZoom = 18,
  });

  final MapController controller;
  final double minZoom;
  final double maxZoom;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;

    void zoomBy(double delta) {
      final c = controller.camera;
      controller.move(c.center, (c.zoom + delta).clamp(minZoom, maxZoom));
    }

    Widget btn(IconData icon, VoidCallback onTap) => Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, color: fg, size: 22),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.add, () => zoomBy(1)),
        const SizedBox(height: 8),
        btn(Icons.remove, () => zoomBy(-1)),
      ],
    );
  }
}
