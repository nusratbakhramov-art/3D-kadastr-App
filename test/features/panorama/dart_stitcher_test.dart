import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/math/rotation.dart';
import 'package:kadastr/features/panorama/models/pano_progress.dart';
import 'package:kadastr/features/panorama/models/sensor_shot.dart';
import 'package:kadastr/features/panorama/models/stitch_outcome.dart';
import 'package:kadastr/features/panorama/stitch/dart_stitcher.dart';
import 'package:kadastr/features/panorama/stitch/raw_plane.dart';
import 'package:kadastr/features/panorama/stitch/work_dir.dart';

/// Butun quvur — dekod → proyeksiya → yechim → qamrov.
///
/// Testlar SUN'IY kadr beradi (`FrameLoader` interfeysi shuning uchun
/// ajratilgan), ya'ni butun quvur telefonsiz, JPEG'siz va sekin
/// dekodersiz yuriladi. Bu MIL-1 QURILMA o'lchovidan OLDIN quvurning
/// to'g'riligini tekshirish imkonini beradi — o'lchov faqat TEZLIKNI
/// aytadi, to'g'rilikni emas.
void main() {
  late Directory parent;

  setUp(() => parent = Directory.systemTemp.createTempSync('pano_st_'));
  tearDown(() {
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  /// Sun'iy sferadan kadr yasaydigan loader.
  ///
  /// Har kadr o'z yo'nalishida sferani «suratga oladi», ya'ni tikilgan
  /// natija asl sferani qayta tiklashi kerak.
  const fw = 48, fh = 48, fov = 60.0;

  int sphereValue(double lat, double lon) {
    final a = ((lon % (2 * math.pi)) / (2 * math.pi) * 11).floor();
    final b = ((lat + math.pi / 2) / math.pi * 5).floor();
    return 40 + ((a * 9 + b * 17) % 180);
  }

  Uint8List shoot(double yawDeg, double pitchDeg) {
    // Tikuvchi ishlatadigan AYNAN o'sha burilish.
    final r = rotationMatrix(
      placementLon(yawDeg),
      pitchDeg * math.pi / 180,
      0,
    );
    final focal = focalPx(fw, fh, fov);
    final out = Uint8List(fw * fh * 3);
    for (int y = 0; y < fh; y++) {
      for (int x = 0; x < fw; x++) {
        final v = cameraRayFromPixel(x + 0.0, y + 0.0, fw / 2, fh / 2, focal);
        final wx = r[0] * v[0] + r[1] * v[1] + r[2] * v[2];
        final wy = r[3] * v[0] + r[4] * v[1] + r[5] * v[2];
        final wz = r[6] * v[0] + r[7] * v[1] + r[8] * v[2];
        final val = sphereValue(
          math.asin(wy.clamp(-1.0, 1.0)),
          math.atan2(wx, wz),
        );
        for (int c = 0; c < 3; c++) {
          out[c * fw * fh + y * fw + x] = val;
        }
      }
    }
    return out;
  }

  /// Yo'l `y<yaw>_p<pitch>` ko'rinishida kodlangan.
  final loader = _SyntheticLoader(shoot);

  List<SensorShot> ring(int n, {double pitch = 0}) => <SensorShot>[
    for (int i = 0; i < n; i++)
      SensorShot(
        path: 'y${(i * 360 / n).toStringAsFixed(3)}_p$pitch',
        yawDeg: i * 360 / n,
        pitchDeg: pitch,
      ),
  ];

  Future<StitchRequest> req(List<SensorShot> shots, {int w = 128}) async =>
      StitchRequest(
        shots: shots,
        workDir: await StitchWorkDir.create(parent),
        outputWidth: w,
        longSideFovDeg: fov,
      );

  group('to‘g‘rilik — sun’iy sfera qayta tiklanadi', () {
    test('to‘liq halqa tikiladi va qamrov o‘lchanadi', () async {
      final out = await stitchSensor(await req(ring(12)), loader);
      expect(out, isA<StitchSuccess>());
      final s = out as StitchSuccess;
      expect(s.width, 128);
      expect(s.height, 64);
      expect(s.verticalCoverDeg, greaterThan(30));
      expect(s.diagnostics['framesUsed'], 12);
    });

    test('KO‘P QATORLI halqa vertikal qamrovni OSHIRADI', () async {
      // Bu test pitch'ning RADIANGA o'girilishini qotiradi: gradusda
      // qoldirilsa 45 gradus 45 RADIAN bo'lib ketadi (≈ 2578°) va
      // kadr butunlay boshqa joyga tushadi. Nol pitch'li halqada bu
      // KO'RINMAYDI — shuning uchun ±45 qatorlari kerak.
      final oneRow = await stitchSensor(await req(ring(12)), loader)
          as StitchSuccess;
      final threeRows = await stitchSensor(
        await req(<SensorShot>[
          ...ring(12),
          ...ring(8, pitch: 45),
          ...ring(8, pitch: -45),
        ]),
        loader,
      ) as StitchSuccess;
      expect(threeRows.diagnostics['framesUsed'], 28);
      expect(
        threeRows.verticalCoverDeg,
        greaterThan(oneRow.verticalCoverDeg + 20),
        reason: '±45 qatorlari sferani vertikal kengaytirishi kerak',
      );
    });

    test('±45 QATORLARI sferani TO‘G‘RI joyga qo‘yadi', () async {
      // «Qamrov oshdi» yetarli DALIL EMAS: pitch gradusda qoldirilsa
      // (45 → 45 radian ≈ 2578°) kadr butunlay boshqa kenglikka tushadi
      // va qamrov BARIBIR oshadi. Shu sababli bu yerda tikilgan piksel
      // asl sfera qiymati bilan solishtiriladi — ±45 qatorlari
      // qamragan kengliklarda.
      Uint8List? got;
      const w = 96, h = 48;
      await stitchSensor(
        await req(<SensorShot>[
          ...ring(12),
          ...ring(8, pitch: 45),
          ...ring(8, pitch: -45),
        ], w: w),
        loader,
        writeOutput: (rgb, w, h) async => got = rgb,
      );

      var checked = 0, match = 0;
      for (int y = 0; y < h; y++) {
        final lat = math.pi / 2 - (y + 0.5) / h * math.pi;
        // FAQAT ±45 qatorlari qamraydigan kengliklar — gorizont
        // qatori bu yerga yetmaydi (kadr vertikal FOV'i ~46°).
        if (lat.abs() < 0.6 || lat.abs() > 1.1) continue;
        for (int x = 0; x < w; x++) {
          final v = got![y * w + x];
          if (v == 0) continue;
          checked++;
          final lon = (w - 1 - x + 0.5) / w * 2 * math.pi;
          if ((v - sphereValue(lat, lon)).abs() <= 1) match++;
        }
      }
      expect(checked, greaterThan(200), reason: '±45 zonasi qamralsin');
      expect(
        match / checked,
        greaterThan(0.80),
        reason: '±45 kadrlari noto‘g‘ri kenglikka tushgan',
      );
    });

    test('bitta qator qamrovi 180° dan ANCHA KICHIK', () async {
      // Qamrov PIKSELDAN o'lchanadi, nisbatdan CHIQARILMAYDI. Nisbat
      // (`h/w·360`) har doim 180 berardi — ya'ni bitta qatorli halqa
      // ham «to'liq sfera» bo'lib ko'rinardi, va farq aynan
      // ko'ruvchining qutblarga o'ragan QORASI bo'lardi.
      final s = await stitchSensor(await req(ring(12)), loader)
          as StitchSuccess;
      expect(s.height / s.width * 360, 180, reason: 'nisbat 180 berardi');
      expect(
        s.verticalCoverDeg,
        lessThan(120),
        reason: 'haqiqiy qamrov ancha kichik',
      );
    });

    test('MIL-1 o‘lchovi QISMAN ekani hisobotga yoziladi', () async {
      // Buni unutish «GO» qarorini qariyb ikki barobar optimistik
      // qilardi — hisobot buni o'zi aytib turishi kerak.
      final s = await stitchSensor(await req(ring(8)), loader) as StitchSuccess;
      expect(s.diagnostics['partialPipeline'], isTrue);
      expect(s.diagnostics['pipelineShareSeen'], kMil1Share);
      expect(s.diagnostics['extrapolated76Ms'], isA<int>());
    });

    test('bosqichlar bo‘yicha vaqt o‘lchanadi', () async {
      final s = await stitchSensor(await req(ring(8)), loader) as StitchSuccess;
      expect(s.diagnostics.containsKey('decodeMs'), isTrue);
      expect(s.diagnostics.containsKey('projectMs'), isTrue);
      expect(s.diagnostics.containsKey('finishMs'), isTrue);
      // Gains/seam/blend HALI YO'Q.
      expect(s.diagnostics.containsKey('gainsMs'), isFalse);
      expect(s.diagnostics.containsKey('blendMs'), isFalse);
    });
  });

  group('nosozliklar', () {
    test('kadrsiz so‘rov RAD ETILADI', () async {
      final out = await stitchSensor(await req(<SensorShot>[]), loader);
      expect(out, isA<StitchFailure>());
      expect((out as StitchFailure).needsMoreImages, isTrue);
    });

    test('HECH BIR kadr o‘qilmasa aniq xato', () async {
      final bad = _SyntheticLoader((yaw, pitch) => null);
      final out = await stitchSensor(await req(ring(4)), bad);
      expect(out, isA<StitchFailure>());
      expect((out as StitchFailure).message, contains('o‘qilmadi'));
      expect(out.diagnostics['framesUnreadable'], 4);
    });

    test('BA’ZI kadr o‘qilmasa qolgani bilan davom etadi', () async {
      // Bitta buzuq fayl butun capture'ni yo'qotmasligi kerak.
      var n = 0;
      final flaky = _SyntheticLoader((yaw, pitch) {
        n++;
        return n == 3 ? null : shoot(yaw, pitch);
      });
      final out = await stitchSensor(await req(ring(12)), flaky);
      expect(out, isA<StitchSuccess>());
      final s = out as StitchSuccess;
      expect(s.diagnostics['framesUsed'], 11);
      expect(s.diagnostics['framesUnreadable'], 1);
      expect(s.diagnostics['unreadable'], hasLength(1));
    });

    test('HALQA YOPILMASA tushunarli xato', () async {
      // Ikki kadr — aylananing atigi kichik qismi. Foydalanuvchiga
      // «ichki xato» emas, nima qilish kerakligi aytilishi kerak.
      final out = await stitchSensor(
        await req(<SensorShot>[
          const SensorShot(path: 'y0_p0.0', yawDeg: 0, pitchDeg: 0),
          const SensorShot(path: 'y20_p0.0', yawDeg: 20, pitchDeg: 0),
        ]),
        loader,
      );
      expect(out, isA<StitchFailure>());
      final f = out as StitchFailure;
      expect(f.needsMoreImages, isTrue);
      expect(f.message, contains('360'));
      // Yiqilishdan keyin ham O'LCHOVLAR qaytadi — «yaqin edi» bilan
      // «umuman uzoq» boshqa nosozlik hisoboti.
      expect(f.diagnostics['bestRowCoverage'], isA<double>());
      expect(f.diagnostics['framesUsed'], 2);
    });
  });

  group('progress', () {
    test('bosqichlar TARTIB bilan keladi va ulush o‘smaydi-kamaymaydi',
        () async {
      final seen = <PanoProgress>[];
      await stitchSensor(await req(ring(6)), loader, onProgress: seen.add);
      expect(seen, isNotEmpty);
      expect(seen.first.phase, StitchPhase.decode);
      expect(seen.last.phase, StitchPhase.finish);
      for (int i = 1; i < seen.length; i++) {
        expect(
          seen[i].overall,
          greaterThanOrEqualTo(seen[i - 1].overall - 1e-9),
          reason: 'progress ORQAGA ketmasligi kerak',
        );
      }
      expect(seen.last.overall, closeTo(1.0, 1e-9));
    });

    test('har kadr uchun bitta dekod hodisasi', () async {
      final seen = <PanoProgress>[];
      await stitchSensor(await req(ring(7)), loader, onProgress: seen.add);
      final decode = seen.where((p) => p.phase == StitchPhase.decode);
      expect(decode, hasLength(7));
      expect(decode.last.done, 7);
      expect(decode.last.total, 7);
    });
  });

  group('chiqish', () {
    test('writeOutput chaqiriladi va o‘lcham to‘g‘ri', () async {
      Uint8List? got;
      int? gw, gh;
      await stitchSensor(
        await req(ring(10), w: 64),
        loader,
        writeOutput: (rgb, w, h) async {
          got = rgb;
          gw = w;
          gh = h;
        },
      );
      expect(gw, 64);
      expect(gh, 32);
      expect(got, hasLength(64 * 32 * 3));
    });

    test('GORIZONTAL FLIP qo‘llanadi', () async {
      // `placementLon` negatsiyasi sferani ko'zguga aylantiradi va
      // oxirgi flip uni qaytaradi. IKKALASI ham shart — flip
      // tushirilsa panorama teskari chiqadi.
      Uint8List? got;
      await stitchSensor(
        await req(ring(12), w: 64),
        loader,
        writeOutput: (rgb, w, h) async => got = rgb,
      );
      // Sferaning kutilgan qiymati bilan solishtiramiz. Flip
      // qo'llangani uchun `x` ustuni `w-1-x` dan o'qiladi.
      const w = 64, h = 32;
      var checked = 0, match = 0;
      for (int y = 4; y < h - 4; y++) {
        for (int x = 0; x < w; x++) {
          final v = got![y * w + x];
          if (v == 0) continue;
          final lat = math.pi / 2 - (y + 0.5) / h * math.pi;
          final lon = (w - 1 - x + 0.5) / w * 2 * math.pi;
          checked++;
          if ((v - sphereValue(lat, lon)).abs() <= 1) match++;
        }
      }
      expect(checked, greaterThan(300));
      expect(match / checked, greaterThan(0.85), reason: 'flip qo‘llanmagan');
    });
  });

  group('kPhaseShare — o‘lchangan ulushlar', () {
    test('yig‘indi AYNAN 1.0', () {
      final sum = kPhaseShare.values.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-12));
    });

    test('har bosqich uchun ulush bor', () {
      for (final p in StitchPhase.values) {
        expect(kPhaseShare[p], isNotNull, reason: '${p.name} ulushi yo‘q');
      }
    });

    test('PROYEKSIYA eng qimmat, blend ikkinchi', () {
      // Rejadagi o'lchov (§5.1): proyeksiya 47 M piksel, blend
      // esa piramida bo'ylab global. Ulushlarni teng qilish progress
      // chizig'ini yolg'onchi qilardi.
      final sorted = kPhaseShare.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      expect(sorted[0].key, StitchPhase.project);
      expect(sorted[1].key, StitchPhase.blend);
    });

    test('MIL-1 ulushi kPhaseShare dan HISOBLANADI', () {
      // Ikki joyda takrorlanmasligi kerak: `extrapolateFull` shu
      // qiymatga tayanadi va `kPhaseShare` o'zgarsa u ham o'zgarishi
      // SHART, aks holda «GO» qarori jimgina buziladi.
      final want = kMil1Phases.fold<double>(0, (a, p) => a + kPhaseShare[p]!);
      expect(kMil1Share, closeTo(want, 1e-12));
      expect(kMil1Share, closeTo(0.56, 1e-12));
      // Ekstrapolyatsiya AYNAN shu songa bo‘ladi.
      expect(
        extrapolateFull(
          const Duration(milliseconds: 560),
          frames: 1,
          targetFrames: 1,
        ).inMilliseconds,
        (560 / kMil1Share).round(),
      );
    });

    test('seam va blend MIL-1 ga KIRMAYDI', () {
      expect(kMil1Phases.contains(StitchPhase.seam), isFalse);
      expect(kMil1Phases.contains(StitchPhase.blend), isFalse);
      expect(kMil1Phases.contains(StitchPhase.gains), isFalse);
      // Ular quvurning 44 %ini tashkil qiladi.
      expect(1 - kMil1Share, closeTo(0.44, 1e-12));
    });
  });

  group('extrapolateFull — MIL-1 qarori', () {
    test('kadr soniga CHIZIQLI', () {
      final a = extrapolateFull(
        const Duration(seconds: 10),
        frames: 8,
        targetFrames: 76,
      );
      final b = extrapolateFull(
        const Duration(seconds: 10),
        frames: 16,
        targetFrames: 76,
      );
      expect(a.inMilliseconds / b.inMilliseconds, closeTo(2, 1e-6));
    });

    test('YETISHMAYOTGAN bosqichlarni ham qo‘shadi', () {
      // Eng muhim da'vo: o'lchov quvurning 56 %ini ko'radi, ya'ni
      // to'liq ish 1/0.56 ≈ 1.79 barobar. Buni tushirib qoldirish
      // «GO» qarorini qariyb ikki barobar optimistik qilardi.
      final full = extrapolateFull(
        const Duration(seconds: 56),
        frames: 76,
        targetFrames: 76,
      );
      expect(full.inSeconds, 100);
    });

    test('8 kadrda 10 s → 76 kadrda ~170 s', () {
      final e = extrapolateFull(
        const Duration(seconds: 10),
        frames: 8,
        targetFrames: 76,
      );
      // 10 · (76/8) / 0.56 = 169.6
      expect(e.inSeconds, closeTo(169, 2));
      // ⚠️ Ya'ni «10 s da 8 kadr» degan xushxabar aslida 120 s
      // chegarasidan OSHIB ketadi — ekstrapolyatsiyasiz bu ko'rinmasdi.
      expect(e.inSeconds, greaterThan(120));
    });
  });
}

class _SyntheticLoader implements FrameLoader {
  _SyntheticLoader(this.make);

  /// `(yawDeg, pitchDeg) → planar RGB` yoki `null` (o'qib bo'lmadi).
  final Uint8List? Function(double yaw, double pitch) make;

  @override
  Future<RawPlane?> load(String path, int targetWidth) async {
    // Yo'l `y<yaw>_p<pitch>` ko'rinishida.
    final m = RegExp(r'^y(-?[\d.]+)_p(-?[\d.]+)$').firstMatch(path);
    if (m == null) return null;
    final bytes = make(double.parse(m.group(1)!), double.parse(m.group(2)!));
    if (bytes == null) return null;
    return RawPlane(width: 48, height: 48, channels: 3, bytes: bytes);
  }
}
