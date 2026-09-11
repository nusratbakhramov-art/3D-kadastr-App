/// 360° ko'ruvchi — ekvirektangulyar tasvirni SFERADA ko'rsatadi.
///
/// NEGA PAKET EMAS. Rejada `panorama_viewer` ko'rsatilgan edi, lekin uning
/// renderer'i `flutter_cube 0.1.1` — Dart 2 davri paketi, ta'mirlanmaydi
/// va ikkalasi ham platforma sozlamalariga tegadi. Bu yerda kerak bo'lgan
/// narsa esa butunlay sof Dart: to'rni `Canvas.drawVertices` ga berish
/// kifoya, qolganini Skia GPU'da bajaradi.
///
/// USUL. Sfera bir marta to'rga bo'linadi (uzunlik × kenglik), har
/// tugunning TEKSTURA koordinatasi QOTIB qoladi, har kadrda esa faqat
/// tugunlar aylantirilib ekranga proyeksiya qilinadi.
///
/// ⚠️ CHOK SHU SABABLI YO'Q. Ekran to'ri bilan qilinganda chokni kesib
/// o'tgan uchburchakda `u` 0.99 dan 0.01 ga sakraydi va Skia ORALIQNI
/// interpolyatsiya qilib butun tasvirni teskarisiga surtib yuboradi. To'r
/// sferada qurilgani uchun `lon = 0` va `lon = 2π` AYRIM tugunlar bo'ladi,
/// ya'ni bunday uchburchak umuman yuzaga kelmaydi.
///
/// ⚠️ TEKSTURA INTERPOLYATSIYASI AFFIN, perspektiv-to'g'ri EMAS —
/// `drawVertices` shunday ishlaydi. Xato uchburchakning ekrandagi
/// kattaligiga bog'liq, shuning uchun to'r ZICH ([_lonSteps] × [_latSteps]):
/// eng kichik FOV'da ham bitta uchburchak ekranning kichik qismini
/// egallaydi va egrilik ko'rinmaydi.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../settings/settings_state.dart' show localeNotifier;

/// To'r zichligi. Ko'paytirish aniqlikni oshiradi va narxi chiziqli —
/// 96×48 da 4 657 tugun, bu kadr uchun hech narsa.
const int _lonSteps = 96;
const int _latSteps = 48;

/// Ko'rish burchagi chegaralari (vertikal, gradus).
///
/// Pastki chegara — eng kuchli yaqinlashtirish. 25° dan pastda
/// ekvirektangulyar tasvirning o'z rezolyutsiyasi tugaydi va
/// yaqinlashtirish faqat piksellarni kattalashtiradi.
const double kMinFovDeg = 25;
const double kMaxFovDeg = 100;
const double kInitialFovDeg = 75;

/// Balandlik chegarasi.
///
/// ⚠️ AYNAN ±90 GA YETKAZILMAYDI: qutbda ko'rish o'qi dunyo «yuqorisi»
/// bilan ustma-ust tushadi va o'ng tomon vektori nolga aylanadi —
/// tasvir bir kadrga aylanib ketardi.
const double kMaxPitchDeg = 89;

class PanoViewerScreen extends StatefulWidget {
  const PanoViewerScreen({super.key, required this.path});

  /// Tikilgan ekvirektangulyar JPEG yo'li.
  final String path;

  @override
  State<PanoViewerScreen> createState() => _PanoViewerScreenState();
}

class _PanoViewerScreenState extends State<PanoViewerScreen> {
  ui.Image? _image;
  String? _error;

  double _yawDeg = 0;
  double _pitchDeg = 0;
  double _fovDeg = kInitialFovDeg;

  // Ishorat boshlangandagi holat — `onScaleUpdate` ular ustiga qo'yadi.
  double _yawAtStart = 0;
  double _pitchAtStart = 0;
  double _fovAtStart = kInitialFovDeg;
  Offset _focalAtStart = Offset.zero;

  Locale get _l => localeNotifier.value;
  String _t(String key) => tr(_l, key);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final File f = File(widget.path);
      if (!f.existsSync()) {
        if (mounted) setState(() => _error = _t('bozor.pano.view.err'));
        return;
      }
      final Uint8List bytes = await f.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } on Object {
      if (mounted) setState(() => _error = _t('bozor.pano.view.err'));
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _yawAtStart = _yawDeg;
    _pitchAtStart = _pitchDeg;
    _fovAtStart = _fovDeg;
    _focalAtStart = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final Offset delta = d.localFocalPoint - _focalAtStart;

    // ⚠️ Burilish FOV'ga PROPORSIONAL. Piksel boshiga qat'iy gradus
    // berilsa, yaqinlashtirilgan holatda barmoq ostidagi manzara
    // otilib ketardi: bir xil surish tor ko'rishda ancha katta
    // burchakka teng bo'ladi.
    final double fov = _fovAtStart;
    final double hFov = fov * (size.width / size.height);

    setState(() {
      _fovDeg = (_fovAtStart / d.scale).clamp(kMinFovDeg, kMaxFovDeg);
      // Manzara barmoq bilan BIRGA yuradi: o'ngga surish ko'rish
      // o'qini chapga buradi.
      _yawDeg = _yawAtStart - delta.dx / size.width * hFov;
      _pitchDeg = (_pitchAtStart + delta.dy / size.height * fov).clamp(
        -kMaxPitchDeg,
        kMaxPitchDeg,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            )
          else if (image == null)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            )
          else
            LayoutBuilder(
              builder: (BuildContext _, BoxConstraints c) {
                final Size size = Size(c.maxWidth, c.maxHeight);
                return GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: (ScaleUpdateDetails d) =>
                      _onScaleUpdate(d, size),
                  child: CustomPaint(
                    size: size,
                    painter: SpherePainter(
                      image: image,
                      yawDeg: _yawDeg,
                      pitchDeg: _pitchDeg,
                      fovDeg: _fovDeg,
                    ),
                  ),
                );
              },
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: _RoundButton(
              icon: Icons.close_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (image != null && _error == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 20,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _t('bozor.pano.view.hint'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sferani ichkaridan chizadi.
///
/// Ajratilgan va ochiq: butun geometriya shu yerda va uni ekransiz,
/// telefonsiz tekshirish mumkin ([projectSphere]).
class SpherePainter extends CustomPainter {
  const SpherePainter({
    required this.image,
    required this.yawDeg,
    required this.pitchDeg,
    required this.fovDeg,
  });

  final ui.Image image;
  final double yawDeg;
  final double pitchDeg;
  final double fovDeg;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final SphereMesh? mesh = projectSphere(
      size: size,
      yawDeg: yawDeg,
      pitchDeg: pitchDeg,
      fovDeg: fovDeg,
      imageW: image.width,
      imageH: image.height,
    );
    if (mesh == null) return;

    final Paint paint = Paint()
      ..shader = ui.ImageShader(
        image,
        // ⚠️ Gorizontal bo'yicha TAKRORLASH: ko'rish chokni kesib
        // o'tganda tekstura koordinatasi tasvir enidan chiqadi va
        // `clamp` o'shanda chekka piksel ustunini cho'zib yuborardi.
        ui.TileMode.repeated,
        // Vertikal bo'yicha esa qisish TO'G'RI: qutbdan narida hech
        // narsa yo'q, takrorlash tasvirni ag'darib qo'yardi.
        ui.TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.low,
      );

    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        mesh.positions,
        textureCoordinates: mesh.texCoords,
        indices: mesh.indices,
      ),
      // Manba tekstura bilan to'liq almashtiriladi.
      BlendMode.src,
      paint,
    );
  }

  @override
  bool shouldRepaint(SpherePainter old) =>
      old.yawDeg != yawDeg ||
      old.pitchDeg != pitchDeg ||
      old.fovDeg != fovDeg ||
      !identical(old.image, image);
}

/// Chizishga tayyor to'r.
class SphereMesh {
  const SphereMesh({
    required this.positions,
    required this.texCoords,
    required this.indices,
  });

  /// Ekran koordinatalari, `[x0, y0, x1, y1, …]`.
  final Float32List positions;

  /// Tekstura koordinatalari — TASVIR PIKSELLARIDA (`ImageShader`
  /// birligi), 0..1 da emas.
  final Float32List texCoords;

  final Uint16List indices;

  int get vertexCount => positions.length ~/ 2;
  int get triangleCount => indices.length ~/ 3;
}

/// Sferani ekranga proyeksiya qiladi.
///
/// Har tugun uchun: dunyo yo'nalishi → kamera fazosi → ekran nuqtasi.
/// Kamera fazosi shu yerda OCHIQ quriladi (`o'ng`, `yuqori`, `oldinga`)
/// va suratga olish tomonidagi kelishuvdan MUSTAQIL — u kamera X'ini
/// chapga qaratadi va bu yerga ko'chirilsa tasvir ko'zguda chiqardi.
///
/// `null` — ko'rinadigan uchburchak qolmadi.
SphereMesh? projectSphere({
  required Size size,
  required double yawDeg,
  required double pitchDeg,
  required double fovDeg,
  required int imageW,
  required int imageH,
  int lonSteps = _lonSteps,
  int latSteps = _latSteps,
}) {
  // Tuval hali o'lchanmagan bo'lishi mumkin (birinchi kadr). Fokus
  // masofasi o'shanda nolga aylanadi va HAMMA tugun (0, 0) ga tushardi —
  // chizilgan narsa bitta nuqta bo'lardi.
  if (size.isEmpty) return null;

  const double deg = math.pi / 180;
  final double yaw = yawDeg * deg;
  final double pitch = pitchDeg.clamp(-kMaxPitchDeg, kMaxPitchDeg) * deg;

  // Ko'rish bazisi. `f` — qarayotgan yo'nalish, `r` — ekranning o'ngi,
  // `u` — yuqorisi.
  final double cp = math.cos(pitch);
  final double fx = cp * math.sin(yaw);
  final double fy = math.sin(pitch);
  final double fz = cp * math.cos(yaw);

  // r = normalize(worldUp × f). `worldUp = (0, 1, 0)` bo'lgani uchun
  // ko'paytma soddalashadi va uzunligi `cos(pitch)` ga teng — shuning
  // uchun qutbda nolga aylanadi va balandlik chegaralangan.
  final double rl = math.sqrt(fz * fz + fx * fx);
  if (rl < 1e-9) return null;
  final double rx = fz / rl;
  final double rz = -fx / rl;
  // u = f × r. `r` ning y'i nol, shuning uchun ko'paytma qisqaradi:
  //   f × r = (fy·rz,  fz·rx − fx·rz,  −fy·rx)
  //
  // ⚠️ `rx` bilan `rz` ni almashtirib yuborish OSON va natijasi jim:
  // `u` endi `f` ga perpendikulyar bo'lmaydi (tekshirildi: pitch 45° da
  // `f·u = 0.5`), ya'ni yuqoriga yoki pastga qaraganda manzara
  // qiyshayib ketadi. Gorizontda esa hammasi to'g'ri ko'rinadi —
  // shuning uchun buni faqat balandlikka qarab sinash tutadi.
  final double ux = fy * rz;
  final double uy = fz * rx - fx * rz;
  final double uz = -fy * rx;

  // Vertikal FOV'dan fokus masofasi.
  final double focal = size.height / 2 / math.tan(fovDeg * deg / 2);
  final double cx = size.width / 2;
  final double cy = size.height / 2;

  final int cols = lonSteps + 1;
  final int rows = latSteps + 1;
  final int n = cols * rows;

  final positions = Float32List(n * 2);
  final texCoords = Float32List(n * 2);
  // Kamera orqasidagi tugun proyeksiya qilinmaydi — uning ekrandagi
  // o'rni ma'nosiz va uchburchakni cho'zib yuborardi.
  final visible = List<bool>.filled(n, false);

  // Uzunlik ustunlari qatordan qatorga TAKRORLANADI, ya'ni ichki
  // tsiklda hisoblash har kadrda 9 000 ga yaqin ortiqcha sin/cos
  // degani — bu ishorat davomida har kadrda qayta yuriladi.
  final sinLon = Float32List(cols);
  final cosLon = Float32List(cols);
  for (int i = 0; i < cols; i++) {
    final double lon = i / lonSteps * 2 * math.pi;
    sinLon[i] = math.sin(lon);
    cosLon[i] = math.cos(lon);
  }

  for (int j = 0; j < rows; j++) {
    // Kenglik: yuqoridan pastga, `+90` … `−90` — ekvirektangulyar
    // tasvirning o'z tartibi.
    final double lat = math.pi / 2 - j / latSteps * math.pi;
    final double clat = math.cos(lat);
    final double slat = math.sin(lat);
    final double v = j / latSteps * imageH;

    for (int i = 0; i < cols; i++) {
      final int k = j * cols + i;

      final double dx = clat * sinLon[i];
      final double dy = slat;
      final double dz = clat * cosLon[i];

      final double zc = dx * fx + dy * fy + dz * fz;
      texCoords[k * 2] = i / lonSteps * imageW;
      texCoords[k * 2 + 1] = v;
      // 1e-3 — nol emas: ko'rish tekisligiga juda yaqin tugun
      // bo'lingandan keyin ulkan koordinata berardi.
      if (zc <= 1e-3) continue;

      final double xc = dx * rx + dz * rz;
      final double yc = dx * ux + dy * uy + dz * uz;

      positions[k * 2] = cx + focal * (xc / zc);
      positions[k * 2 + 1] = cy - focal * (yc / zc);
      visible[k] = true;
    }
  }

  // Faqat TO'RT burchagi ham ko'rinadigan katakcha chiziladi. Qisman
  // ko'rinadiganini kesish kerak bo'lardi; katakchalar mayda va ular
  // ko'rish konusidan ancha tashqarida yotadi, ya'ni tashlab yuborish
  // ekranda hech narsa qoldirmaydi.
  final indices = <int>[];
  for (int j = 0; j < latSteps; j++) {
    for (int i = 0; i < lonSteps; i++) {
      final int a = j * cols + i;
      final int b = a + 1;
      final int c = a + cols;
      final int d = c + 1;
      if (!visible[a] || !visible[b] || !visible[c] || !visible[d]) continue;
      indices..addAll(<int>[a, b, c])..addAll(<int>[b, d, c]);
    }
  }
  if (indices.isEmpty) return null;

  return SphereMesh(
    positions: positions,
    texCoords: texCoords,
    indices: Uint16List.fromList(indices),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.45),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    ),
  );
}
