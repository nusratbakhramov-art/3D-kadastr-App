/// Sof Dart tikuvchi — sensor burchaklaridan panorama.
///
/// 13-qadam (MIL-1) qamrovi: dekod → proyeksiya → yechim → qamrov.
/// Ekspozitsiya tenglashtirish (14), chok yo'nalishi (15) va ko'p bandli
/// aralashtirish (16) HALI YO'Q — ular alohida qadamlarda qo'shiladi va
/// [StitchStats.phases] ularni bo'sh ko'rsatadi.
///
/// ⚠️ MIL-1 O'LCHOVINING QAMROVI CHEKLANGAN. Bu quvur yakuniy quvurning
/// atigi **56 %ini** ko'radi (`kPhaseShare` bo'yicha: dekod 0.10 +
/// proyeksiya 0.44 + yakun 0.02). Ya'ni «8 kadr N soniyada tikildi»
/// degan raqamni to'g'ridan-to'g'ri 76 kadrga ko'chirib bo'lmaydi —
/// [extrapolateFull] ekstrapolyatsiyani seam va blend ulushini ham
/// qo'shib hisoblaydi. Buni unutish «GO» qarorini ikki barobar
/// optimistik qilardi.
library;

import 'dart:async';
import 'dart:typed_data';

import '../math/rotation.dart';
import '../models/pano_progress.dart';
import '../models/sensor_shot.dart';
import '../models/stitch_outcome.dart';
import 'project.dart';
import 'raw_plane.dart';
import 'work_dir.dart';

/// Kadrni diskdan o'qib, PLANAR xom holga keltiradigan narsa.
///
/// Interfeys sifatida ajratilgan, chunki haqiqiy dekoder (`package:image`)
/// og'ir va sekin — unit testlar sun'iy kadr beradi va butun quvurni
/// telefonsiz, JPEG'siz yurgizadi. Bu MIL-1 dan OLDIN quvurning
/// to'g'riligini tekshirish imkonini beradi.
abstract class FrameLoader {
  /// [path] dagi kadrni [targetWidth] eniga tushirib qaytaradi.
  ///
  /// ⚠️ EXIF ORIENTATSIYASI shu yerda qo'llanishi SHART. `cv.imread` uni
  /// avtomatik qo'llaydi; Dart dekoderi qilmasa uzun tomon almashadi,
  /// `focalPx` 1.78× xato chiqadi va HECH NARSA tikilmaydi. Bu rejadagi
  /// eng jim va eng halokatli farq (§4.2).
  Future<RawPlane?> load(String path, int targetWidth);
}

/// Tikish so'rovi.
class StitchRequest {
  const StitchRequest({
    required this.shots,
    required this.workDir,
    this.outputWidth = 3072,
    this.longSideFovDeg = 67.3,
    this.blendPower = 16,
  }) : assert(outputWidth > 0);

  final List<SensorShot> shots;
  final StitchWorkDir workDir;

  /// Tuval eni. Balandligi har doim yarmi — ekvirektangulyar 2:1.
  final int outputWidth;

  final double longSideFovDeg;
  final int blendPower;

  int get canvasW => outputWidth;
  int get canvasH => outputWidth ~/ 2;
}

/// Bosqichlar bo'yicha o'lchov — MIL-1 qarorining asosi.
class StitchStats {
  StitchStats();

  final Map<StitchPhase, Duration> phases = <StitchPhase, Duration>{};

  int framesUsed = 0;
  int framesUnreadable = 0;
  int canvasW = 0;
  int canvasH = 0;

  Duration get total =>
      phases.values.fold(Duration.zero, (a, b) => a + b);

  Map<String, Object?> toJson() => <String, Object?>{
    'framesUsed': framesUsed,
    'framesUnreadable': framesUnreadable,
    'canvas': '${canvasW}x$canvasH',
    'totalMs': total.inMilliseconds,
    for (final e in phases.entries) '${e.key.name}Ms': e.value.inMilliseconds,
  };
}

/// MIL-1 ekstrapolyatsiyasi — o'lchangan qisman quvurdan TO'LIQ ishga.
///
/// [measured] — shu quvur (dekod + proyeksiya + yakun) bilan o'lchangan
/// vaqt, [frames] — o'sha o'lchovdagi kadr soni, [targetFrames] — haqiqiy
/// capture (76).
///
/// Ikki ko'paytiruvchi:
///  1. **Kadr soni** — proyeksiya kadrlar soniga chiziqli;
///  2. **Yetishmayotgan bosqichlar** — o'lchov quvurning 56 %ini ko'radi,
///     ya'ni to'liq ish `1 / 0.56 ≈ 1.79` barobar.
///
/// Ikkinchisini tushirib qoldirish «GO» qarorini QARIYB IKKI BAROBAR
/// optimistik qilardi — reja buni ochiq ogohlantiradi.
Duration extrapolateFull(
  Duration measured, {
  required int frames,
  int targetFrames = 76,
}) {
  assert(frames > 0);
  // ⚠️ [kMil1Share] dan HISOBLANADI, bu yerda yozib qo'yilmaydi —
  // `kPhaseShare` o'zgarsa ekstrapolyatsiya jimgina noto'g'ri bo'lib
  // qolardi va «GO» qarori buzilardi.
  final double scaled =
      measured.inMicroseconds * (targetFrames / frames) / kMil1Share;
  return Duration(microseconds: scaled.round());
}

/// Kadrlarni tikadi.
///
/// [onProgress] — UI uchun; isolate ichida ishlatilsa `SendPort` ga
/// uzatiladi.
Future<StitchOutcome> stitchSensor(
  StitchRequest req,
  FrameLoader loader, {
  void Function(PanoProgress)? onProgress,
  Future<void> Function(Uint8List rgb, int w, int h)? writeOutput,
  String outputPath = '',
}) async {
  final stats = StitchStats()
    ..canvasW = req.canvasW
    ..canvasH = req.canvasH;
  final clock = Stopwatch()..start();

  if (req.shots.isEmpty) {
    return const StitchFailure('Kadr yo‘q', needsMoreImages: true);
  }

  // ── 1. Dekod va kesh ──────────────────────────────────────────────────
  final phaseClock = Stopwatch()..start();
  final loaded = <int, RawPlane>{};
  final unreadable = <String>[];

  for (int i = 0; i < req.shots.length; i++) {
    final shot = req.shots[i];
    // Kadr eni FOV va tuvaldan kelib chiqadi. Birinchi kadrni o'qimaguncha
    // uning o'lchamini bilmaymiz, shuning uchun to'liq enda so'raymiz va
    // loader o'zi kichraytiradi — u kadr o'lchamini biladi.
    final plane = await loader.load(shot.path, 0);
    if (plane == null) {
      unreadable.add(shot.path.split('/').last);
      continue;
    }
    loaded[i] = plane;
    onProgress?.call(
      PanoProgress(
        phase: StitchPhase.decode,
        done: i + 1,
        total: req.shots.length,
        elapsed: clock.elapsed,
      ),
    );
  }
  stats.phases[StitchPhase.decode] = phaseClock.elapsed;
  stats.framesUnreadable = unreadable.length;
  stats.framesUsed = loaded.length;

  if (loaded.isEmpty) {
    return StitchFailure(
      'Hech bir kadr o‘qilmadi',
      needsMoreImages: true,
      diagnostics: stats.toJson(),
    );
  }

  // ── 2. Proyeksiya ─────────────────────────────────────────────────────
  phaseClock
    ..reset()
    ..start();
  final canvas = PanoCanvas(
    width: req.canvasW,
    height: req.canvasH,
  );

  int placed = 0;
  for (final entry in loaded.entries) {
    final shot = req.shots[entry.key];
    final plane = entry.value;
    final double focal = focalPx(
      plane.width,
      plane.height,
      req.longSideFovDeg,
    );
    final map = buildFrameMap(
      // ⚠️ `placementLon` ALLAQACHON radianda va yaw NEGATSIYA qilingan.
      // Ilovaning yaw'i telefon o'ngga burilganda o'sadi, proyektor
      // longitudasi esa teskari tomonga (kamera X chapga qaraydi).
      // Negatsiyasiz har kadr o'z o'rnining KO'ZGUSIGA tushadi —
      // manbada o'lchangan: mos feature qoldig'i 5 px dan 218 px ga
      // chiqqan va 70 kadrdan 30 tasi umuman tuzatilmagan.
      rotation: rotationMatrix(
        placementLon(shot.yawDeg),
        shot.pitchDeg * _degToRad,
        shot.rollDeg * _degToRad,
      ),
      frameW: plane.width,
      frameH: plane.height,
      focal: focal,
      canvasW: req.canvasW,
      canvasH: req.canvasH,
      blendPower: req.blendPower,
    );
    compositeFrame(
      canvas,
      map,
      <Uint8List>[for (int c = 0; c < plane.channels; c++) plane.plane(c)],
      plane.width,
      plane.height,
      entry.key,
    );
    placed++;
    onProgress?.call(
      PanoProgress(
        phase: StitchPhase.project,
        done: placed,
        total: loaded.length,
        elapsed: clock.elapsed,
      ),
    );
  }
  stats.phases[StitchPhase.project] = phaseClock.elapsed;

  // ── 3. Yakun: qamrov va chiqish ───────────────────────────────────────
  phaseClock
    ..reset()
    ..start();
  final scan = selectBand(rowCoverage(canvas), req.canvasW);
  // ⚠️ IKKALASI HAM SHART: `placementLon` negatsiyasi va shu flip.
  // `placementLon` ni «tuzatib» flip'dan qutulib bo'lmaydi — o'shanda
  // kadrlar ORASIDAGI kelishuv buziladi. Ekvirektangulyar tasvirning
  // gorizontal flip'i aynan `lon → −lon`, ya'ni chok qoldirmaydi.
  final rgb = flipHorizontal(
    resolveCanvas(canvas),
    req.canvasW,
    req.canvasH,
    3,
  );

  if (scan.band == null) {
    stats.phases[StitchPhase.finish] = phaseClock.elapsed;
    return StitchFailure(
      'Halqa yopilmadi — bir joyda turib to‘liq 360° aylaning',
      needsMoreImages: true,
      diagnostics: <String, Object?>{...stats.toJson(), ...scan.toJson()},
    );
  }

  // Vertikal qamrov PIKSELDAN o'lchanadi, nisbatdan CHIQARILMAYDI —
  // sababi `StitchSuccess.verticalCoverDeg` izohida.
  final double verticalCoverDeg = scan.band!.height / req.canvasH * 180;

  if (writeOutput != null) {
    await writeOutput(rgb, req.canvasW, req.canvasH);
  }
  stats.phases[StitchPhase.finish] = phaseClock.elapsed;
  onProgress?.call(
    PanoProgress(
      phase: StitchPhase.finish,
      done: 1,
      total: 1,
      elapsed: clock.elapsed,
    ),
  );

  return StitchSuccess(
    path: outputPath,
    width: req.canvasW,
    height: req.canvasH,
    verticalCoverDeg: verticalCoverDeg,
    diagnostics: <String, Object?>{
      ...stats.toJson(),
      ...scan.toJson(),
      if (unreadable.isNotEmpty) 'unreadable': unreadable,
      // MIL-1 qarori uchun — o'lchov QISMAN quvurniki ekani ochiq
      // yozib qo'yiladi.
      'partialPipeline': true,
      'pipelineShareSeen': kMil1Share,
      'extrapolated76Ms': extrapolateFull(
        stats.total,
        frames: loaded.length,
      ).inMilliseconds,
    },
  );
}

/// Planar tasvirni gorizontal aylantiradi.
///
/// Ekvirektangulyar tuvalda bu aynan `lon → −lon`, ya'ni CHOK
/// QOLDIRMAYDI — oddiy tasvirdan farqli, bu yerda chap va o'ng chetlar
/// allaqachon tutashgan.
Uint8List flipHorizontal(Uint8List src, int w, int h, int channels) {
  final out = Uint8List(src.length);
  for (int c = 0; c < channels; c++) {
    final int base = c * w * h;
    for (int y = 0; y < h; y++) {
      final int row = base + y * w;
      for (int x = 0; x < w; x++) {
        out[row + (w - 1 - x)] = src[row + x];
      }
    }
  }
  return out;
}

const double _degToRad = 3.1415926535897932 / 180;
