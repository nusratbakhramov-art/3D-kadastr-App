import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Pastki tugmaning diametri — halqalar shundan boshlanadi.
///
/// `home_screen.dart` dagi `_ImageFab.size` bilan bir xil bo'lishi shart;
/// `fab_pulse_test.dart` shuni qo'riqlaydi.
const double fabSize = 56;

/// Tugmadan tarqaladigan halqalar — "tirik" ekanini bildiradi.
///
/// Ikkala pastki tugma (qo'ng'iroq va chat) uchun. Halqa rangi tugmaniki
/// bilan bir xil beriladi: PNG'lar o'z ranglarini ichida olib yuradi va
/// undan rang o'qib bo'lmaydi.
///
/// ⚠️ SCROLL PAYTIDA TO'XTAYDI. Takrorlanuvchi animatsiya har kadrda qayta
/// chizadi; tugma ko'rinmay turganda ham aylanaverishi bekorga quvvat
/// yeydi. Shuning uchun [visible] kuzatiladi va kontroller to'xtatiladi.
/// Boshqa ekran ustiga ochilganda esa Flutter'ning `TickerMode` i o'zi
/// pauza qiladi.
///
/// ⚠️ Halqalar tugma CHEGARASIDAN TASHQARIGA chiziladi va bu ataylab:
/// o'lcham 56pt bo'lib qoladi, aks holda `Scaffold` FAB uchun kattaroq joy
/// ajratib, tugmani burchakdan surib yuborardi.
class FabPulse extends StatefulWidget {
  const FabPulse({
    super.key,
    required this.visible,
    required this.color,
    required this.child,
  });

  final ValueListenable<bool> visible;
  final Color color;
  final Widget child;

  @override
  State<FabPulse> createState() => FabPulseState();
}

class FabPulseState extends State<FabPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // Sekin va bosiq: tez puls diqqatni tortib, bezovta qiladi.
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (widget.visible.value) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    widget.visible.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Halqalar teginishni USHLAMASIN — tugma ustidagi bosish o'ziga
        // borishi kerak.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: const Size.square(fabSize),
              painter: PulsePainter(t: _c.value, color: widget.color),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class PulsePainter extends CustomPainter {
  const PulsePainter({required this.t, required this.color});

  /// 0..1 — takrorlanuvchi faza.
  final double t;
  final Color color;

  /// Ikkita halqa yetadi: uchtasi "shovqin" bo'lib ko'rinadi.
  static const int rings = 2;

  /// Eng katta halqa tugma radiusidan shuncha marta katta.
  static const double maxScale = 1.95;

  /// Halqaning eng yuqori shaffofligi.
  static const double peakAlpha = 0.30;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r0 = size.shortestSide / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < rings; i++) {
      // Halqalar teng oraliqda ketadi — biri so'nayotganda ikkinchisi
      // endi chiqadi.
      final p = (t + i / rings) % 1.0;
      final alpha = (1 - p) * peakAlpha;
      if (alpha < 0.004) continue; // ko'rinmaydi — chizmaymiz
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, r0 * (1 + (maxScale - 1) * p), paint);
    }
  }

  @override
  bool shouldRepaint(PulsePainter old) => old.t != t || old.color != color;
}
