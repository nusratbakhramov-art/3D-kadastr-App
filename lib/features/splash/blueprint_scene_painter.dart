import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Splash sahnasining ikkita qatlami.
///
/// Original render (940×1672) oflayn ikkiga bo'lingan:
///   * [plate] — sof fon: gradient, xira to'r, logo ortidagi yog'du. Unda
///     uyning izi yo'q, shuning uchun chizishdan oldin hech narsa oshkor
///     bo'lmaydi.
///   * [lines] — faqat kontent (uy, daraxtlar, o'simliklar, yer to'ri) qora
///     fonda. `plate + lines` = original (o'rtacha xato ~0.5/255).
///
/// Uchinchi qatlam — piksel QACHON chizilishini bildiruvchi `blueprint-order`
/// xaritasi — endi ishlatilmaydi: ochilish geodezik tarqalish emas, pastdan
/// tepaga bir tekis supurish. Asset o'chirilmagan (qaytarish uchun turibdi).
class BlueprintSceneImages {
  const BlueprintSceneImages({required this.plate, required this.lines});

  final ui.Image plate;
  final ui.Image lines;

  static const String _platePath = 'assets/branding/splash/blueprint-plate.webp';
  static const String _linesPath = 'assets/branding/splash/blueprint-lines.webp';

  static Future<BlueprintSceneImages> load() async {
    final images = await Future.wait([
      _decode(_platePath),
      _decode(_linesPath),
    ]);
    return BlueprintSceneImages(plate: images[0], lines: images[1]);
  }

  static Future<ui.Image> _decode(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  void dispose() {
    plate.dispose();
    lines.dispose();
  }
}

/// Sahnani chizadi va uni [progress] bo'yicha "chizilayotgandek" ochadi.
///
/// Ochilish — PASTDAN TEPAGA yuradigan gorizontal front: [progress] bilan
/// front [_contentBottom] dan [_contentTop] gacha bir tekis ko'tariladi,
/// ostidagi hamma narsa ko'rinadi, ustidagisi hali yo'q. Front ortida tor
/// yorug' tasma qoladi — "qalam uchi". Maska bitta vertikal gradient bilan
/// beriladi, shuning uchun na shader, na oldindan tayyorlangan kadr kerak.
class BlueprintScenePainter extends CustomPainter {
  const BlueprintScenePainter({
    required this.images,
    required this.progress,
    this.penGlow = 1.0,
    this.sceneOpacity = 1.0,
  });

  final BlueprintSceneImages images;

  /// 0 — faqat fon, 1 — sahna to'liq (original kadr).
  final double progress;

  /// Chizayotgan "qalam uchi" — ochilish frontidagi yorqin tasma.
  final double penGlow;

  /// Butun sahnaning ko'rinishi (yashil splashdan o'tishda).
  final double sceneOpacity;

  static const Size imageSize = Size(940, 1672);

  // Chizmadagi kontentning haqiqiy balandligi (o'lchangan: birinchi yorug'
  // piksel y=690, oxirgisi y=1622). Front shu oraliqda yuradi — bo'sh osmonni
  // supurishga vaqt ketmaydi, shuning uchun "bir temp" ko'zga bir tekis
  // ko'rinadi.
  static const double _contentTop = 660;
  static const double _contentBottom = 1640;

  /// Front chetining yumshoqligi (rasm piksellarida). Kichik = o'tkirroq chiziq.
  static const double _frontSoftness = 24;

  /// Front ortidagi yorug' tasmaning balandligi (rasm piksellarida).
  static const double _glowBand = 120;

  /// Rasmning ekrandagi joyi (BoxFit.cover).
  static Rect sceneRect(Size size) {
    final scale = math.max(
      size.width / imageSize.width,
      size.height / imageSize.height,
    );
    final w = imageSize.width * scale;
    final h = imageSize.height * scale;
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  /// Frontning [dst] ichidagi nisbiy holati (0 — tepa, 1 — past).
  static double _frontStop(Rect dst, double p) {
    final y = ui.lerpDouble(_contentBottom, _contentTop, p.clamp(0.0, 1.0))!;
    return y / imageSize.height;
  }

  static const Color _opaque = Color(0xFFFFFFFF);
  static const Color _clear = Color(0x00FFFFFF);

  /// Chizilgan qismning maskasi: front ostida — to'liq, ustida — yo'q.
  static ui.Shader _wipe(Rect dst, double front, double soft) {
    final a = (front - soft).clamp(0.0, 1.0);
    final b = (front + soft).clamp(0.0, 1.0);
    return ui.Gradient.linear(
      Offset(dst.left, dst.top),
      Offset(dst.left, dst.bottom),
      const <Color>[_clear, _clear, _opaque, _opaque],
      <double>[0.0, math.min(a, b), b, 1.0],
    );
  }

  /// Qalam uchi: front chizig'ida yonadi va ORTIDA (pastda) so'nadi.
  static ui.Shader _pen(Rect dst, double front, double soft, double band) {
    final a = (front - soft).clamp(0.0, 1.0);
    final f = front.clamp(0.0, 1.0);
    final c = (front + band).clamp(0.0, 1.0);
    return ui.Gradient.linear(
      Offset(dst.left, dst.top),
      Offset(dst.left, dst.bottom),
      const <Color>[_clear, _clear, _opaque, _clear, _clear],
      <double>[0.0, math.min(a, f), f, math.max(f, c), 1.0],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final dst = sceneRect(size);
    final src = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    final full = Offset.zero & size;
    final opacity = sceneOpacity.clamp(0.0, 1.0);

    // Fon — har doim ko'rinadi (chizishdan oldin ham sahna "qog'ozi" turadi).
    canvas.drawImageRect(
      images.plate,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );

    if (progress <= 0.0 || opacity <= 0.0 || dst.height <= 0) return;

    final front = _frontStop(dst, progress);
    final soft = _frontSoftness / imageSize.height;

    // 1) Chizilgan qism: lines, vertikal maska orqali, fonga QO'SHILADI.
    canvas.saveLayer(
      full,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    canvas.drawRect(dst, Paint()..shader = _wipe(dst, front, soft));
    canvas.drawImageRect(
      images.lines,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();

    // 2) Qalam uchi: front ortidagi tor tasma yana bir marta qo'shiladi va
    // xiralashtiriladi — chiziq "yonib" tug'ilayotgandek ko'rinadi.
    final glow = penGlow.clamp(0.0, 1.0) * opacity;
    if (glow > 0.01) {
      canvas.saveLayer(
        full,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Color.fromRGBO(0, 0, 0, 0.85 * glow)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
      );
      canvas.drawRect(
        dst,
        Paint()..shader = _pen(dst, front, soft, _glowBand / imageSize.height),
      );
      canvas.drawImageRect(
        images.lines,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.srcIn,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(BlueprintScenePainter old) =>
      old.progress != progress ||
      old.penGlow != penGlow ||
      old.sceneOpacity != sceneOpacity ||
      old.images != images;
}
