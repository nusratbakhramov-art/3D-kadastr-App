// 360° panorama, 13-qadam (MIL-1) — 8 kadrni TIKIB vaqtni o'lchash.
// Reja: docs/panorama-360-plan.md §9 (13-qadam).
//
// SAVOL: sof Dart bilan 76 kadrli panoramani telefonda tikish amaliymi?
// Bu butun yondashuvning QAROR DARVOZASI.
//
// ⚠️ O'LCHOV QISMAN QUVURNI KO'RADI. Bu bosqichda gains (14), seam (15) va
//    multi-band blend (16) HALI YOZILMAGAN, ya'ni o'lchov yakuniy quvurning
//    atigi ~56 %ini ko'radi (`kMil1Share`). Shuning uchun chiqishda IKKI
//    raqam bor: xom o'lchov va `extrapolateFull` bergan 76 kadrli
//    ekstrapolyatsiya. QAROR IKKINCHISIGA qarab qabul qilinadi — birinchisiga
//    qarash «GO» ni qariyb ikki barobar optimistik qilardi.
//
// ⚠️ NEGA AOT (`--profile`) MAJBURIY: `bench_decode.sh` dagi sabab bilan bir
//    xil — butun quvur sof Dart, JIT'da bir necha barobar sekin.
//
// ⚠️ EMULYATOR/SIMULYATOR YARAMAYDI — natija host protsessorini ko'rsatadi.
//
// Chiqish (mashina o'qiy oladigan yagona qator):
//   PANOSTITCH frames=N measured_ms=NNN decode_ms=NN project_ms=NN
//              finish_ms=NN extrapolated76_s=NNN coverage_deg=NN.N verdict=GO|NO
//
// Kadrlar qayerdan olinadi:
//   1. --dart-define=PANO_STITCH_DIR=<qurilmadagi papka>
//   2. Android: <external files dir>/pano_frames/
//   3. <app documents dir>/pano_frames/
//
// Papkadagi fayl nomlari `y<yaw>_p<pitch>.jpg` bo'lishi kerak, masalan
// `y000_p0.jpg`, `y045_p0.jpg` — burchaklar shundan o'qiladi. Haqiqiy
// capture ekrani (19-qadam) ularni o'zi shunday nomlaydi.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kadastr/features/panorama/models/pano_progress.dart';
import 'package:kadastr/features/panorama/models/sensor_shot.dart';
import 'package:kadastr/features/panorama/models/stitch_outcome.dart';
import 'package:kadastr/features/panorama/stitch/dart_stitcher.dart';
import 'package:kadastr/features/panorama/stitch/image_frame_loader.dart';
import 'package:kadastr/features/panorama/stitch/work_dir.dart';
import 'package:path_provider/path_provider.dart';

/// «GO» chegarasi — 76 kadrli TO'LIQ tikish shundan oshmasligi kerak.
///
/// 120 s: foydalanuvchi suratga olishga ~2 daqiqa sarflaydi, tikish undan
/// uzoq davom etsa oqim tashlab ketiladi.
const int kGoThresholdSeconds = 120;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MIL-1: kadrlarni tikib vaqtni o‘lchash', (tester) async {
    const bool isDebug = bool.fromEnvironment('dart.vm.product') == false &&
        bool.fromEnvironment('dart.vm.profile') == false;
    if (isDebug) {
      debugPrint(
        '⚠️⚠️ DEBUG (JIT) rejimi — raqamlar BIR NECHA BAROBAR sekin. '
        'To‘g‘ri buyruq: bash tool/pano/bench_stitch.sh',
      );
    }

    final dir = await _framesDir();
    if (dir == null) {
      debugPrint(
        'PANOSTITCH xato=kadrlar_topilmadi — papkani ko‘rsating: '
        '--dart-define=PANO_STITCH_DIR=<yo‘l>, fayllar `y<yaw>_p<pitch>.jpg`',
      );
      return;
    }

    final shots = _shotsFrom(dir);
    if (shots.length < 2) {
      debugPrint('PANOSTITCH xato=kadr_yetarli_emas found=${shots.length}');
      return;
    }

    final parent = await getApplicationDocumentsDirectory();
    await StitchWorkDir.purgeStale(parent, olderThan: Duration.zero);
    final wd = await StitchWorkDir.create(parent);

    try {
      final req = StitchRequest(shots: shots, workDir: wd);
      final loader = ImageFrameLoader(
        workDir: wd,
        canvasW: req.canvasW,
        longSideFovDeg: req.longSideFovDeg,
        readBytes: (p) async {
          final f = File(p);
          return f.existsSync() ? f.readAsBytes() : null;
        },
      );

      final clock = Stopwatch()..start();
      var lastPhase = StitchPhase.decode;
      final outcome = await stitchSensor(
        req,
        loader,
        onProgress: (p) {
          if (p.phase != lastPhase) {
            debugPrint('PANOSTITCH bosqich=${p.phase.name} t=${clock.elapsed}');
            lastPhase = p.phase;
          }
        },
      );
      clock.stop();

      if (outcome is StitchFailure) {
        debugPrint(
          'PANOSTITCH xato=tikilmadi msg="${outcome.message}" '
          'diag=${outcome.diagnostics}',
        );
        return;
      }

      final s = outcome as StitchSuccess;
      final d = s.diagnostics;
      final extrapolated = extrapolateFull(
        Duration(milliseconds: d['totalMs']! as int),
        frames: d['framesUsed']! as int,
      );
      final verdict =
          extrapolated.inSeconds <= kGoThresholdSeconds ? 'GO' : 'NO';

      debugPrint(
        'PANOSTITCH frames=${d['framesUsed']} '
        'measured_ms=${d['totalMs']} '
        'decode_ms=${d['decodeMs']} '
        'project_ms=${d['projectMs']} '
        'finish_ms=${d['finishMs']} '
        'extrapolated76_s=${extrapolated.inSeconds} '
        'coverage_deg=${s.verticalCoverDeg.toStringAsFixed(1)} '
        'verdict=$verdict',
      );
      debugPrint(
        'PANOSTITCH_NOTE o‘lchov quvurning ${(kMil1Share * 100).round()} '
        '%ini ko‘radi — QAROR extrapolated76_s ga qarab qabul qilinadi, '
        'measured_ms ga EMAS. Chegara: ${kGoThresholdSeconds}s.',
      );
      expect(s.width, req.canvasW);
    } finally {
      await wd.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// Kadrlar papkasini topadi.
Future<Directory?> _framesDir() async {
  const override = String.fromEnvironment('PANO_STITCH_DIR');
  if (override.isNotEmpty) {
    final d = Directory(override);
    if (d.existsSync()) return d;
  }
  if (Platform.isAndroid) {
    final ext = await getExternalStorageDirectory();
    if (ext != null) {
      final d = Directory('${ext.path}/pano_frames');
      if (d.existsSync()) return d;
    }
  }
  final docs = await getApplicationDocumentsDirectory();
  final d = Directory('${docs.path}/pano_frames');
  return d.existsSync() ? d : null;
}

/// `y<yaw>_p<pitch>.jpg` nomlaridan burchaklarni o'qiydi.
///
/// Nomdan o'qish ATAYLAB: benchmark uchun capture ekrani (19-qadam) hali
/// yo'q va sensor yozuvlari ham yo'q. Haqiqiy oqimda burchaklar sessiya
/// hisobotidan keladi.
List<SensorShot> _shotsFrom(Directory dir) {
  final re = RegExp(r'^y(-?[\d.]+)_p(-?[\d.]+)\.(jpe?g|JPE?G)$');
  final out = <SensorShot>[];
  for (final e in dir.listSync()) {
    if (e is! File) continue;
    final m = re.firstMatch(e.path.split('/').last);
    if (m == null) continue;
    out.add(
      SensorShot(
        path: e.path,
        yawDeg: double.parse(m.group(1)!),
        pitchDeg: double.parse(m.group(2)!),
      ),
    );
  }
  out.sort((a, b) => a.yawDeg.compareTo(b.yawDeg));
  return out;
}
