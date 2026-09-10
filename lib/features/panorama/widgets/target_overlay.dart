/// Keyingi kadrni AYNAN TURGAN JOYIDA — kamera preview'i ustida chizadi.
///
/// Butun g'oya shu: nishon — bu son emas, XONADAGI JOY. «O'ngga 20° buriling»
/// deyish odamni burchak chamalashga majbur qiladi; devorga aylana qo'yish esa
/// uni o'sha yerga OLIB BORADI va u yaqinlashayotganini o'z ko'zi bilan
/// ko'radi.
///
/// Ekrandan tashqarida aylana YOLG'ON bo'lardi — u chetga yopishib, nishon
/// go'yo o'sha yerdadek ko'rsatardi. Shuning uchun u STRELKAGA aylanadi va
/// nishon haqiqatan ko'rinadigan bo'lgandagina yana joyga qaytadi.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../models/capture_guidance.dart';

/// «Tekislandi» belgisi — brend yashili.
///
/// Manbada `#4ADE80` edi; bu yerda [AppColors.splashGreen] ishlatiladi:
/// u ham uy uslubiga mos, ham yorqinroq, ya'ni jonli video ustida
/// ko'rinishi yaxshiroq.
const Color kAlignedTint = AppColors.splashGreen;

/// «Yaqin qoldi» belgisi.
///
/// Uy palitrasida bunga mos rang YO'Q — bu ilova bezagi emas, kamera
/// tasviri ustidagi FUNKSIONAL signal va u ixtiyoriy sahnaga qarshi
/// ajralib turishi kerak.
const Color kHighlightedTint = Color(0xFFFACC15);

/// Nishon markeri ekranda QAYERGA tushadi — yoki `null`, ya'ni strelka.
///
/// SOF funksiya, ataylab ajratilgan: `BoxFit.cover` shartnomasining butun
/// arifmetikasi va ko'rinish qarori shu yerda, ya'ni ular `Canvas` siz
/// tekshiriladi. Rassomning ichida qolganda bu qarorlar faqat «yiqilmadi»
/// darajasida sinalardi.
///
/// [px] — nishonning kadr markazidan piksel siljishi (`TargetSight
/// .offsetPixels`). [markerRadius] — o'sha darajadagi marker radiusi.
@visibleForTesting
Offset? markerAt(
  Size size,
  Size imageSize,
  Offset? px,
  double markerRadius,
) {
  if (px == null) return null;
  if (imageSize.width <= 0 || imageSize.height <= 0) return null;

  // ⚠️ `BoxFit.cover` SHARTNOMASI: masshtab `max(w/iw, h/ih)`. `min` bo'lsa
  // bu `BoxFit.contain` bo'lardi va nishon ko'rsatayotgan narsasidan
  // siljirdi.
  final double scale = math.max(
    size.width / imageSize.width,
    size.height / imageSize.height,
  );
  final Offset centre = Offset(size.width / 2, size.height / 2);
  final Offset p = centre + Offset(px.dx * scale, px.dy * scale);
  final double margin = markerRadius + 6;

  // Chegara TO'RT TOMONDAN HAM QAMRAB OLUVCHI (`>=` / `<=`): aynan
  // `size.width - margin` ga tushgan nishon MARKER chizadi, strelka emas.
  if (p.dx >= margin &&
      p.dx <= size.width - margin &&
      p.dy >= margin &&
      p.dy <= size.height - margin) {
    return p;
  }
  return null;
}

/// Daraja bo'yicha marker radiusi. Telefon yaqinlashgani sari O'SADI —
/// progress son o'qimasdan ko'rinadi.
@visibleForTesting
double markerRadiusFor(GuidanceLevel level) => switch (level) {
  GuidanceLevel.far => 17,
  GuidanceLevel.approaching => 24,
  GuidanceLevel.highlighted => 31,
  GuidanceLevel.aligned => 36,
};

class TargetOverlay extends StatelessWidget {
  const TargetOverlay({
    required this.sight,
    required this.imageSize,
    required this.stability,
    super.key,
  });

  /// Sensorlar joylashguncha, yoki halqada so'raladigan narsa qolmaganda
  /// `null`. Nishon halqasi baribir chiziladi — ekran miltillamasin.
  final TargetSight? sight;

  /// Olinadigan tasvirning O'Z piksellaridagi o'lchami, portret holatda.
  final Size imageSize;

  /// Telefon tekislangan nishonda qimirlamay turganda 0..1.
  final double stability;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _TargetPainter(
          sight: sight,
          imageSize: imageSize,
          stability: stability,
        ),
        // ⚠️ `Size.infinite` — ota-ona bergan bo'shliqni to'liq egallaydi.
        // Aniq o'lcham qo'yish overlay'ni preview'dan ajratardi.
        size: Size.infinite,
      ),
    );
  }
}

class _TargetPainter extends CustomPainter {
  _TargetPainter({
    required this.sight,
    required this.imageSize,
    required this.stability,
  });

  final TargetSight? sight;
  final Size imageSize;
  final double stability;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final TargetSight? s = sight;
    final Color tint = _tint(s?.level);

    _drawReticle(canvas, centre, tint);
    if (s == null) return;

    if (s.level == GuidanceLevel.aligned && stability > 0) {
      _drawStability(canvas, centre);
    }

    // ⚠️ Nishon KO'RINADIMI — bu uning kadr ichiga tushishi bilan BIR XIL
    // NARSA EMAS.
    //
    // Preview `BoxFit.cover` bilan ko'rsatiladi, ya'ni baland ekranda
    // tasvirning o'z chap va o'ng chetlari QIRQILADI va foydalanuvchiga
    // yetib bormaydi. O'sha qirqilgan hoshiyada turgan nishon kadr ichida,
    // lekin ko'rinmaydi — uni ekran chetiga qisib chizish esa «u ana u
    // yerda» deb YOLG'ON aytish bo'lardi, strelka aynan shuning o'rniga
    // bor.
    //
    // Shuning uchun ko'rinish geometriyadan OLINMAYDI, EKRANDAGI haqiqiy
    // piksellarga qarab hal qilinadi. `s.onScreen` ATAYLAB ishlatilmaydi.
    final double radius = markerRadiusFor(s.level);
    final Offset? at = markerAt(size, imageSize, s.offsetPixels, radius);

    if (at != null) {
      _drawMarker(canvas, at, tint, radius);
    } else {
      _drawArrow(canvas, centre, s.arrowRadians, size);
    }
  }

  Color _tint(GuidanceLevel? level) => switch (level) {
    GuidanceLevel.aligned => kAlignedTint,
    GuidanceLevel.highlighted => kHighlightedTint,
    GuidanceLevel.approaching => Colors.white,
    _ => Colors.white70,
  };

  void _drawReticle(Canvas canvas, Offset centre, Color tint) {
    canvas
      ..drawCircle(
        centre,
        27,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = tint,
      )
      ..drawCircle(centre, 4, Paint()..color = tint.withValues(alpha: 0.45));
  }

  void _drawStability(Canvas canvas, Offset centre) {
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: 34),
      -math.pi / 2,
      2 * math.pi * stability.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = kAlignedTint,
    );
  }

  void _drawMarker(Canvas canvas, Offset at, Color tint, double radius) {
    canvas
      ..drawCircle(at, radius, Paint()..color = tint.withValues(alpha: 0.18))
      ..drawCircle(
        at,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = tint,
      );
  }

  void _drawArrow(Canvas canvas, Offset centre, double radians, Size size) {
    final double reach = math.min(size.width, size.height) * 0.22;
    final Offset at =
        centre + Offset(math.cos(radians), math.sin(radians)) * reach;

    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(radians);

    final Path head = Path()
      ..moveTo(26, 0)
      ..lineTo(-10, -19)
      ..lineTo(-2, 0)
      ..lineTo(-10, 19)
      ..close();

    canvas
      // Qora soya — strelka OQ devorda ham ko'rinsin.
      ..drawPath(
        head,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      )
      ..drawPath(head, Paint()..color = Colors.white)
      ..restore();
  }

  /// ⚠️ RO'YXAT ANIQ. `onScreen` shu yerda o'qiladi, lekin [paint] da
  /// UMUMAN ishlatilmaydi — u shunga qaramay qayta chizishni keltirib
  /// chiqarishi kerak, chunki u o'zgargani nishonning kadrga kirib-chiqqanini
  /// bildiradi.
  ///
  /// `angleErrorDeg` esa ATAYLAB YO'Q: u sensor tezligida uzluksiz
  /// o'zgaradi va uni qo'shish har tikda qayta chizishga olib kelardi,
  /// vizual natija esa o'zgarmasdi.
  ///
  /// Ikkala tomonga «tartibga solish» — `onScreen` ni olib tashlash yoki
  /// `angleErrorDeg` ni qo'shish — kompilyatsiya xatosisiz xatti-harakatni
  /// o'zgartiradi.
  @override
  bool shouldRepaint(_TargetPainter old) =>
      old.sight?.offsetPixels != sight?.offsetPixels ||
      old.sight?.level != sight?.level ||
      old.sight?.onScreen != sight?.onScreen ||
      old.sight?.arrowRadians != sight?.arrowRadians ||
      old.stability != stability ||
      old.imageSize != imageSize;
}
