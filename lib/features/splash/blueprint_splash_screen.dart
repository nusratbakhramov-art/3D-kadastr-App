import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;

import '../../theme/app_colors.dart';
import 'blueprint_scene_painter.dart';

/// Splash — "blueprint".
///
/// Bitta sahna, bitta g'oya:
///   1) lockup (3D logo + "3D kadastr") referens renderdagi joyida paydo
///      bo'ladi;
///   2) neon uy o'zini CHIZADI — ochilish fronti PASTDAN TEPAGA, bir tekis
///      tezlikda ko'tariladi (ortida "qalam uchi" yonib turadi);
///   3) yakuniy kadr referens renderning aynan o'zi.
///
/// Eski [AnimatedSplashScreen] ning kirish qismi (logo pastdan ko'tarilib
/// aylanadi, matn markazdan o'ngga chiqadi) bu ekrandan OLIB TASHLANDI — u
/// blueprint sahnasidan oldin "eski splash yana bir marta o'ynadi" bo'lib
/// ko'rinardi. Eski ekranning o'zi o'chirilmagan: main.dart dagi bitta flag
/// bilan qaytariladi.
class BlueprintSplashScreen extends StatefulWidget {
  const BlueprintSplashScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<BlueprintSplashScreen> createState() => _BlueprintSplashScreenState();
}

class _BlueprintSplashScreenState extends State<BlueprintSplashScreen>
    with SingleTickerProviderStateMixin {
  // DEBUG: true bo'lsa animatsiya tugagach uyga o'tmasdan qayta o'ynaydi.
  static const bool _loopForTesting = false;

  /// Logo endi aylanmaydi — 90 kadrli aylanishdan faqat YUZ (front) pozasi
  /// kerak, referens renderdagi kabi. Qolgan kadrlar eski splash uchun
  /// assetlarda turaveradi.
  static const int _logoRestFrame = 5;
  static const int _decodeWidth = 700; // manba 780px

  // ---------------------------------------------------------------------
  // Lockup o'lchamlari — REFERENS RENDER PIKSELLARIDA (940×1672).
  // Shu tanlov tufayli dizayn birligi = referens piksel bo'ladi va lockup
  // renderdagi logo bilan aynan bir joyda, bir o'lchamda turadi.
  // O'lchangan qiymatlar: logo kvadrati 182px, markazi (266, 355);
  // matn 432px keng, markazi (598.5, 368.5).
  // ---------------------------------------------------------------------

  /// Logo kadri (780×780 webp) ichida tasvirning o'zi qutining shuncha
  /// qismini egallaydi — qolgani aylanish uchun bo'sh joy edi.
  static const double _logoArtFill = 0.455;

  /// Logo tasviri referensda 182px → kadr qutisi 182 / 0.455.
  static const double _logoBox = 182 / _logoArtFill; // 400

  /// Guruh markazi (anchor) logo va matn markazlarining o'rtasi; quyidagi
  /// siljishlar shu markazdan hisoblanadi.
  static const Offset _lockupAnchorInImage = Offset(432.25, 361.75);
  static const Offset _logoOffset = Offset(-166.25, -6.75);
  static const Offset _textOffset = Offset(166.25, 6.75);

  /// Matn referensda shuncha piksel keng — shrift o'lchami shunga qarab
  /// hisoblanadi (MTSCompact referensdagi shriftdan farq qiladi, shuning
  /// uchun kegl emas, EN moslanadi).
  static const double _textTargetWidth = 432;

  /// Lockup shu DIZAYN qutisi ichida quriladi — anchor atrofida simmetrik va
  /// ikkala bolani ham to'liq o'z ichiga oladi (logo qutisi 400, matnning
  /// o'ng cheti anchordan 382.25). Quti tashqarida bitta [FittedBox] bilan
  /// ekranga masshtablanadi, shuning uchun ichkarida constraint hech qachon
  /// qisilmaydi va matn o'ng tomondan "sig'may qolmaydi".
  static const Size _lockupBox = Size(800, 440);

  /// KO'RINADIGAN kontentning chetlari (anchorga nisbatan, dizayn birligida):
  /// chapda logo tasvirining cheti (−166.25 − 91), o'ngda matnning oxiri
  /// (166.25 + 216). [_lockupBox] dan tor — quti ichida bo'sh joy ham bor.
  static const double _contentLeft = -257.25;
  static const double _contentRight = 382.25;

  /// Lockup ekran chetiga shundan yaqin kelmaydi.
  static const double _minSideMargin = 16;

  /// Sahna yuklanmaguncha va yashildan o'tishda ko'rinadigan fon — referens
  /// renderning chekka rangi.
  static const Color _sceneBase = Color(0xFF051008);

  static const Cubic _crispOut = Cubic(0.16, 1.0, 0.3, 1.0);

  late final AnimationController _controller;
  late final Animation<double> _bridgeT; // native yashil → blueprint foni
  late final Animation<double> _lockupT; // logo + matn joyida paydo bo'ladi
  late final Animation<double> _drawT; // sahna o'zini chizadi

  ui.Image? _logo;
  BlueprintSceneImages? _scene;
  double? _fontSize;
  bool _completed = false;
  bool _started = false;

  // Ikki zarb — animatsiya QAYERGADIR yetganda uriladi, harakat davomida
  // emas. Bayroq emas, hisoblagich: tick har kadrda ishlaydi.
  static const List<double> _hapticTimes = [
    0.08, // chizish boshlandi
    0.92, // sahna tugadi
  ];
  int _hapticI = 0;

  static String _framePath(int i) =>
      'assets/branding/logo-frames/frame_${i.toString().padLeft(3, '0')}.webp';

  @override
  void initState() {
    super.initState();
    // Yagona sozlagich — pastdagi oraliqlar shu davomiylikning ulushlari.
    // 2900ms da taqsimot:
    //    0– 261ms  BRIDGE  native splashning yashilidan blueprint foniga
    //   58– 464ms  LOCKUP  logo + matn o'z joyida paydo bo'ladi
    //  232–2668ms  DRAW    sahna o'zini chizadi
    // 2668–2900ms  SETTLE  qalam uchi so'nadi
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2900),
    );
    _bridgeT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.09, curve: Curves.easeOut),
    );
    _lockupT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.02, 0.16, curve: _crispOut),
    );
    // BIR TEMP: chizish tezligi boshidan oxirigacha o'zgarmaydi — front
    // pastdan tepaga bir tekis ko'tariladi.
    _drawT = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.08, 0.92, curve: Curves.linear),
    );
    _controller.addStatusListener(_handleStatus);
    _controller.addListener(_handleHaptics);
    _loadAndStart();
  }

  /// Har zarbni sozlagich undan o'tganda bir marta uradi. Taymer emas,
  /// sozlagich QIYMATI bo'yicha — assetlar yuklanishini kutgan animatsiyadan
  /// hech qachon ajralib ketmaydi.
  void _handleHaptics() {
    final v = _controller.value;
    while (_hapticI < _hapticTimes.length && v >= _hapticTimes[_hapticI]) {
      switch (_hapticI) {
        case 0:
          HapticFeedback.lightImpact();
        case 1:
          HapticFeedback.selectionClick();
      }
      _hapticI++;
    }
  }

  Future<void> _loadAndStart() async {
    if (_started) return;
    _started = true;
    try {
      final results = await Future.wait<Object>([
        _decodeLogo(),
        BlueprintSceneImages.load(),
      ]);
      _logo = results[0] as ui.Image;
      _scene = results[1] as BlueprintSceneImages;
    } catch (_) {
      // Asset topilmasa ham splash qotib qolmasin — animatsiya baribir ketadi.
    }
    if (!mounted) return;
    setState(() {});
    _controller.forward();
  }

  Future<ui.Image> _decodeLogo() async {
    final data = await rootBundle.load(_framePath(_logoRestFrame));
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: _decodeWidth,
    );
    return (await codec.getNextFrame()).image;
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_loopForTesting) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _hapticI = 0;
        _controller
          ..reset()
          ..forward();
      });
      return;
    }
    if (!_completed) {
      _completed = true;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) widget.onComplete();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.removeListener(_handleHaptics);
    _controller.dispose();
    _logo?.dispose();
    _scene?.dispose();
    super.dispose();
  }

  /// Matnni referensdagi kenglikka moslaydigan kegl. Bir marta o'lchanadi.
  double _resolveFontSize() {
    final cached = _fontSize;
    if (cached != null) return cached;
    const probe = 100.0;
    final tp = TextPainter(
      text: const TextSpan(
        text: _brandText,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w600,
          fontSize: probe,
          letterSpacing: -0.0109 * probe,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final size = tp.width > 0 ? probe * _textTargetWidth / tp.width : 90.0;
    _fontSize = size;
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Dizayn birligi = referens piksel, shuning uchun masshtab rasmnikining
    // o'zi: lockup har qanday ekranda renderdagi logo o'rniga aniq tushadi.
    final dst = BlueprintScenePainter.sceneRect(size);
    var scale = dst.width / BlueprintScenePainter.imageSize.width;
    var anchorX = dst.left + _lockupAnchorInImage.dx * scale;
    final anchorY = dst.top + _lockupAnchorInImage.dy * scale;

    // Uzun (20:9 va tor) telefonlarda sahna "cover" bilan yon tomonlardan
    // qirqiladi va matnning o'ng cheti ekrandan chiqib ketardi. Kerak bo'lsa
    // lockupni ozgina kichraytirib, ichkariga suramiz — referens kompozitsiya
    // sig'adigan ekranlarda esa hech narsa o'zgarmaydi.
    final available = size.width - 2 * _minSideMargin;
    final contentWidth = (_contentRight - _contentLeft) * scale;
    if (available > 0 && contentWidth > available) {
      final shrink = available / contentWidth;
      scale *= shrink;
      anchorX = dst.left + _lockupAnchorInImage.dx * scale;
    }
    final overshootRight =
        (anchorX + _contentRight * scale) - (size.width - _minSideMargin);
    if (overshootRight > 0) anchorX -= overshootRight;
    final overshootLeft = _minSideMargin - (anchorX + _contentLeft * scale);
    if (overshootLeft > 0) anchorX += overshootLeft;

    final anchor = Offset(anchorX, anchorY);
    final boxW = _lockupBox.width * scale;
    final boxH = _lockupBox.height * scale;

    // Material — matn uchun: usiz `Text` MaterialApp'ning "sen Material'ni
    // unutding" uslubini meros qilib oladi va tagi SARIQ ikki chiziq bilan
    // chizilgan bo'lib chiqadi.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final bridge = _bridgeT.value.clamp(0.0, 1.0);
          final lockup = _lockupT.value.clamp(0.0, 1.0);
          final draw = _drawT.value.clamp(0.0, 1.0);
          final scene = _scene;
          // Qalam uchi chizish davomida yonadi, oxirida so'nadi.
          final pen = draw <= 0.0 || draw >= 1.0
              ? 0.0
              : math.min(1.0, math.min(draw * 14, (1 - draw) * 9));

          return ColoredBox(
            color: Color.lerp(AppColors.splashGreen, _sceneBase, bridge)!,
            child: Stack(
              children: [
                // Blueprint sahnasi: fon + o'zini chizadigan uy.
                if (scene != null && bridge > 0.0)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: BlueprintScenePainter(
                        images: scene,
                        progress: draw,
                        penGlow: pen,
                        sceneOpacity: bridge,
                      ),
                    ),
                  ),
                // Logo + matn lockup'i — boshidanoq referens joyida.
                Positioned(
                  left: anchor.dx - boxW / 2,
                  top: anchor.dy - boxH / 2,
                  width: boxW,
                  height: boxH,
                  child: Opacity(
                    opacity: lockup,
                    child: Transform.scale(
                      scale: ui.lerpDouble(0.94, 1.0, lockup)!,
                      // Lockup DIZAYN birliklarida quriladi va ekranga bitta
                      // masshtab bilan tushadi: ichkaridagi constraint doim
                      // 800×440, shuning uchun matn hech qachon o'ng tomondan
                      // sig'may qolmaydi.
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: SizedBox(
                          width: _lockupBox.width,
                          height: _lockupBox.height,
                          child: _buildLockup(_resolveFontSize()),
                        ),
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

  /// Lockup dizayn birliklarida — joylashtirish va o'lchov tashqarida.
  Widget _buildLockup(double fontSize) {
    final logo = _logo;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Transform.translate(
          offset: _textOffset,
          child: _BrandText(fontSize: fontSize),
        ),
        Transform.translate(
          offset: _logoOffset,
          child: SizedBox(
            width: _logoBox,
            height: _logoBox,
            child: logo == null
                ? const SizedBox.shrink()
                : RawImage(
                    image: logo,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
          ),
        ),
      ],
    );
  }
}

const String _brandText = '3D kadastr';

class _BrandText extends StatelessWidget {
  const _BrandText({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Brend so'zi ataylab backenddan olinmaydi: splash birinchi kadrni i18n
    // bundle yuklanishidan oldin chizadi, tr() kaliti xom ko'rinib qolardi.
    // Rangi ikkala fonda ham bir xil — referens renderda ham matn qora.
    return Text(
      _brandText,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        color: const Color(0xFF011606),
        letterSpacing: -0.0109 * fontSize,
        // Ataylab: `Text` meros qilib oladigan uslubda dekoratsiya bo'lsa
        // (MaterialApp'ning sariq ikki chizig'i), aynan shu uni o'chiradi.
        decoration: TextDecoration.none,
      ),
    );
  }
}
