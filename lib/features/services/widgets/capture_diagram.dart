/// Xonani videoga olish qo'llanmasi uchun sxematik chizmalar.
///
/// Har bir chizma yuqoridan ko'rinish (plan): xona konturi, yurish yo'li va
/// kamera qaragan yo'nalishlar. To'g'ri usullar yashil, xatolar qizil va X
/// belgisi bilan. Rasm emas, `CustomPainter` — mavzu (light/dark) bilan birga
/// rangini o'zgartiradi va hech qanday asset talab qilmaydi.
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

enum CaptureDiagramKind {
  /// Ichkariga qarab bir aylanish.
  loop,

  /// Bir yuqoriga, bir pastga qaragan aylanish.
  highLow,

  /// Devorlarga qiya burchakdan qarash.
  oblique,

  /// XATO: bir joyda turib aylanish.
  spinInPlace,

  /// XATO: burchakda keskin burish.
  cornerSnap,

  /// XATO: yaqin devorga parallel yurish.
  wallParallel,
}

class CaptureDiagram extends StatelessWidget {
  const CaptureDiagram({super.key, required this.kind, required this.correct});

  final CaptureDiagramKind kind;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        correct ? AppColors.callGreenDeep : AppColors.chatRedDeep;
    final line = isDark
        ? Colors.white.withValues(alpha: 0.28)
        : AppColors.textBlack.withValues(alpha: 0.22);

    return AspectRatio(
      aspectRatio: 160 / 100,
      child: CustomPaint(
        painter: _DiagramPainter(kind: kind, accent: accent, line: line),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter({
    required this.kind,
    required this.accent,
    required this.line,
  });

  final CaptureDiagramKind kind;
  final Color accent;
  final Color line;

  static const double _w = 160;
  static const double _h = 100;

  /// Xona konturi.
  static final Rect _room = const Rect.fromLTWH(10, 10, 140, 80);

  /// Yurish yo'li (xona ichida, devorlardan uzoqroq).
  static final RRect _loop = RRect.fromRectAndRadius(
    const Rect.fromLTWH(36, 28, 88, 44),
    const Radius.circular(20),
  );

  static const Offset _centre = Offset(80, 50);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _w, size.height / _h);

    final wall = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    final path = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = accent;
    final ray = Paint()
      ..color = accent.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    _drawRoom(canvas, wall);

    switch (kind) {
      case CaptureDiagramKind.loop:
        _drawLoop(canvas, path, fill, ray);
      case CaptureDiagramKind.highLow:
        _drawHighLow(canvas, path, fill);
      case CaptureDiagramKind.oblique:
        _drawOblique(canvas, path, fill, ray);
      case CaptureDiagramKind.spinInPlace:
        _drawSpinInPlace(canvas, path, fill);
      case CaptureDiagramKind.cornerSnap:
        _drawCornerSnap(canvas, path, fill);
      case CaptureDiagramKind.wallParallel:
        _drawWallParallel(canvas, path, fill, ray);
    }

    canvas.restore();
  }

  // ---------------------------------------------------------------- chizmalar

  void _drawRoom(Canvas canvas, Paint wall) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(_room, const Radius.circular(6)),
      wall,
    );
    // Eshik o'rni — xona ekanini bildiradi.
    canvas.drawLine(const Offset(10, 62), const Offset(10, 78),
        wall..strokeWidth = 3.2);
    wall.strokeWidth = 1.6;
  }

  void _drawLoop(Canvas canvas, Paint path, Paint fill, Paint ray) {
    final loop = Path()..addRRect(_loop);
    canvas.drawPath(_dashed(loop, 6, 4), path);
    for (final t in const [0.12, 0.42, 0.72]) {
      _arrowOn(canvas, loop, t, fill);
    }
    // Kamera ichkariga — markazga qaragan konuslar.
    for (final t in const [0.0, 0.25, 0.5, 0.75]) {
      final p = _pointOn(loop, t);
      _cone(canvas, p, (_centre - p).direction, 15, ray, fill);
    }
  }

  void _drawHighLow(Canvas canvas, Paint path, Paint fill) {
    // Bitta aylana — lekin ikki marta: bir yuqoriga, bir pastga qaragan holda.
    final loop = Path()..addRRect(_loop);
    canvas.drawPath(_dashed(loop, 6, 4), path);
    _arrowOn(canvas, loop, 0.12, fill);
    _arrowOn(canvas, loop, 0.62, fill);

    // Aylana boshlanadigan nuqta — shu yerda to'xtab egiladi.
    final start = _pointOn(loop, 0.87);
    canvas.drawCircle(start, 3.4, fill);

    // Egish o'lchagichi: yuqoriga va pastga ikki tomonlama strelka.
    const gauge = Offset(80, 50);
    canvas.drawLine(
        gauge + const Offset(0, -13), gauge + const Offset(0, 13), path);
    _arrowHead(canvas, gauge + const Offset(0, -13), -math.pi / 2, fill, 5);
    _arrowHead(canvas, gauge + const Offset(0, 13), math.pi / 2, fill, 5);
    canvas.drawLine(
        gauge + const Offset(-6, 0), gauge + const Offset(6, 0), path);
  }

  void _drawOblique(Canvas canvas, Paint path, Paint fill, Paint ray) {
    final loop = Path()..addRRect(_loop);
    canvas.drawPath(_dashed(loop, 6, 4), path);
    _arrowOn(canvas, loop, 0.12, fill);
    _arrowOn(canvas, loop, 0.62, fill);
    // Devorlarga tik emas, qiya (diagonal) qaraydigan ko'rish burchaklari:
    // tashqi normaldan ~50 daraja burilgan.
    for (final (t, turn) in const <(double, double)>[
      (0.04, 0.9),
      (0.29, -0.9),
      (0.54, 0.9),
      (0.79, -0.9),
    ]) {
      final from = _pointOn(loop, t);
      final outward = (from - _centre).direction;
      _cone(canvas, from, outward + turn, 21, ray, fill);
    }
  }

  void _drawSpinInPlace(Canvas canvas, Paint path, Paint fill) {
    // Bir joyda turib yaw — yon siljish yo'q.
    canvas.drawCircle(_centre, 3.4, fill);
    final arc = Path()
      ..addArc(Rect.fromCircle(center: _centre, radius: 20), -2.5, 4.6);
    canvas.drawPath(arc, path);
    final end = _pointOn(arc, 1.0);
    _arrowHead(canvas, end, _tangentOn(arc, 0.99), fill, 5);
    _cross(canvas, const Offset(126, 26), 9, fill);
  }

  void _drawCornerSnap(Canvas canvas, Paint path, Paint fill) {
    // Burchakkacha sekin, keyin keskin burilish — zanjir uziladi.
    final walk = Path()
      ..moveTo(40, 74)
      ..lineTo(112, 74);
    canvas.drawPath(_dashed(walk, 6, 4), path);
    _arrowOn(canvas, walk, 0.55, fill);
    // Keskin 90° burilish.
    final snap = Path()
      ..moveTo(112, 74)
      ..lineTo(112, 34);
    canvas.drawPath(snap, path);
    _arrowHead(canvas, const Offset(112, 34), -math.pi / 2, fill, 5);
    // Uzilish belgisi.
    canvas.drawLine(const Offset(106, 66), const Offset(118, 58), path);
    canvas.drawLine(const Offset(106, 58), const Offset(118, 66), path);
    _cross(canvas, const Offset(40, 26), 9, fill);
  }

  void _drawWallParallel(Canvas canvas, Paint path, Paint fill, Paint ray) {
    // Yaqin devor — kadrni to'ldirib turgani ko'rinsin deb qalin chiziladi.
    canvas.drawLine(
      const Offset(12, 18),
      const Offset(12, 82),
      Paint()
        ..color = fill.color.withValues(alpha: 0.55)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    // Unga parallel yurish.
    final walk = Path()
      ..moveTo(38, 24)
      ..lineTo(38, 78);
    canvas.drawPath(_dashed(walk, 6, 4), path);
    _arrowOn(canvas, walk, 0.62, fill);
    // Kamera esa tik devorga qaragan.
    for (final y in const [30.0, 50.0, 70.0]) {
      _cone(canvas, Offset(38, y), math.pi, 22, ray, fill);
    }
    _cross(canvas, const Offset(116, 28), 9, fill);
  }

  // ------------------------------------------------------------- yordamchilar

  /// Yo'lni uzuq-uzuq qilib qaytaradi.
  Path _dashed(Path source, double dash, double gap) {
    final out = Path();
    for (final PathMetric metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        out.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gap;
      }
    }
    return out;
  }

  Offset _pointOn(Path path, double t) {
    final metric = path.computeMetrics().first;
    return metric.getTangentForOffset(metric.length * t)?.position ??
        Offset.zero;
  }

  double _tangentOn(Path path, double t) {
    final metric = path.computeMetrics().first;
    final tangent = metric.getTangentForOffset(metric.length * t);
    if (tangent == null) return 0;
    return math.atan2(tangent.vector.dy, tangent.vector.dx);
  }

  void _arrowOn(Canvas canvas, Path path, double t, Paint fill) {
    _arrowHead(canvas, _pointOn(path, t), _tangentOn(path, t), fill, 5);
  }

  /// Uchburchak strelka: [at] nuqtada, [angle] yo'nalishida.
  void _arrowHead(
      Canvas canvas, Offset at, double angle, Paint fill, double size) {
    final tip = at + Offset(math.cos(angle), math.sin(angle)) * size;
    final left = at +
        Offset(math.cos(angle + 2.5), math.sin(angle + 2.5)) * (size * 0.9);
    final right = at +
        Offset(math.cos(angle - 2.5), math.sin(angle - 2.5)) * (size * 0.9);
    canvas.drawPath(Path()..addPolygon([tip, left, right], true), fill);
  }

  /// Kamera ko'rish burchagi — [from] nuqtadan [angle] yo'nalishga konus.
  void _cone(Canvas canvas, Offset from, double angle, double length,
      Paint ray, Paint fill) {
    const spread = 0.38;
    final a = from + Offset(math.cos(angle - spread), math.sin(angle - spread)) * length;
    final b = from + Offset(math.cos(angle + spread), math.sin(angle + spread)) * length;
    canvas.drawPath(
      Path()..addPolygon([from, a, b], true),
      Paint()..color = ray.color.withValues(alpha: 0.12),
    );
    canvas.drawLine(from, a, ray);
    canvas.drawLine(from, b, ray);
    canvas.drawCircle(from, 2.4, fill);
  }

  /// Xato belgisi.
  void _cross(Canvas canvas, Offset at, double r, Paint fill) {
    final stroke = Paint()
      ..color = fill.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      at,
      r,
      Paint()..color = fill.color.withValues(alpha: 0.12),
    );
    final d = r * 0.42;
    canvas.drawLine(at + Offset(-d, -d), at + Offset(d, d), stroke);
    canvas.drawLine(at + Offset(d, -d), at + Offset(-d, d), stroke);
  }

  @override
  bool shouldRepaint(_DiagramPainter old) =>
      old.kind != kind || old.accent != accent || old.line != line;
}
