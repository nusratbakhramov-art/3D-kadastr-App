// 360° panorama, 3-qadam (MIL-0) — JPEG dekod/resize/enkod mikro-benchmark.
// Reja: docs/panorama-360-plan.md §9 (3-qadam) va §5.
//
// SAVOL: 76 ta 4K kadrni sof Dart bilan dekodlash telefonda amaliymi?
// Agar yo'q bo'lsa — 4-qadam (native `kadastr/pano_codec` kanali) majburiy
// bo'ladi. Shu fayl aynan shu qarorga kerak bo'lgan to'rtta raqamni beradi.
//
// ⚠️ NEGA HOST EMAS, TELEFON: benchmark host mashinada yurgizilsa raqam
//    3–5× optimistik chiqadi va qaror soxta bo'ladi.
//
// ⚠️ NEGA AOT (`--profile`) MAJBURIY: `flutter test integration_test/...`
//    ilovani DEBUG (JIT) da yig'adi. `package:image` — sof Dart, ya'ni
//    uning ichki sikllari JIT'da AOT'ga qaraganda bir necha barobar sekin
//    ishlaydi. Debug raqami bilan «native kanal kerak» degan xulosa chiqarish
//    — eng qimmat xato. To'g'ri buyruq:
//
//      bash tool/pano/bench_decode.sh          # ichida flutter drive --profile
//
//    Rejim chiqishdagi `PANOBENCH_SRC ... mode=` da ko'rinadi; debug bo'lsa
//    test baland ovozda ogohlantiradi (lekin YIQILMAYDI — bu o'lchov vositasi,
//    darvoza emas).
//
// Chiqish (mashina o'qiy oladigan yagona qator):
//   PANOBENCH decodeJpg_ms=NNN resizeArea_ms=NN encodeJpg_ms=NNN peakRss_mb=NNN
//
// Manba JPEG qayerdan olinadi (shu tartibda, birinchi topilgani ishlatiladi):
//   1. --dart-define=PANO_BENCH_JPEG=<qurilmadagi to'liq yo'l>
//   2. Android: <external files dir>/pano_bench.jpg
//      (`adb push` shu yerga yozadi — bench_decode.sh o'zi qiladi)
//   3. <app documents dir>/pano_bench.jpg
//   4. hech biri yo'q bo'lsa — SINTETIK kadr (tool/pano/gen_test_jpeg.dart).
//      ⚠️ Sintetika shovqinli, ya'ni dekod PESSIMISTIK chiqadi.

import 'dart:io';

// `Uint8List` `foundation` orqali keladi — `dart:typed_data` ni alohida
// import qilish `unnecessary_import` beradi.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../tool/pano/gen_test_jpeg.dart'
    show buildSyntheticPanoFrame, kPanoBenchWidth, kPanoBenchHeight;

/// Har o'lchov shuncha marta takrorlanadi; natija — MEDIANA.
/// O'rtacha EMAS: telefonda termal throttling va GC pauzalari bitta-ikkita
/// takrorni ikki barobar cho'zadi, o'rtacha shundan buziladi.
const int _reps = 10;

/// Kadr keshining reja §5.2 dagi eng katta darajasi.
const int _cacheWidth = 702;
const int _cacheHeight = 1248;

/// Chiqish equirect o'lchami (reja §10.1 — 3072×1536 QARORI).
const int _outWidth = 3072;
const int _outHeight = 1536;

/// Chiqish JPEG sifati.
const int _outQuality = 90;

/// Qurilmadan qidiriladigan fayl nomi.
const String _benchFileName = 'pano_bench.jpg';

const String _jpegPathOverride = String.fromEnvironment('PANO_BENCH_JPEG');

const String _buildMode =
    kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

/// `ProcessInfo.currentRss` monoton emas — GC dan keyin tushadi. Shuning
/// uchun har takrordan keyin namuna olinadi va MAKSIMUM saqlanadi.
int _peakRss = 0;

void _sampleRss() {
  final rss = ProcessInfo.currentRss;
  if (rss > _peakRss) _peakRss = rss;
}

/// Juft sonli takrorda ikki o'rtaning o'rtachasi.
double _medianUs(List<int> samples) {
  final s = List<int>.from(samples)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2].toDouble() : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2.0;
}

int _medianMs(List<int> samples) => (_medianUs(samples) / 1000).round();

String _spread(List<int> samples) {
  final s = List<int>.from(samples)..sort();
  return 'min=${(s.first / 1000).round()} max=${(s.last / 1000).round()}';
}

class _BenchSource {
  const _BenchSource(this.bytes, this.width, this.height, this.origin);

  final Uint8List bytes;
  final int width;
  final int height;
  final String origin;
}

/// JPEG sarlavhasidan o'lchamni oladi (to'liq dekodsiz) va kerak bo'lsa
/// kadrni 3840×2160 ga keltiradi. Bu ish O'LCHOVDAN TASHQARIDA bajariladi.
_BenchSource _normalize(Uint8List bytes, String origin) {
  final info = img.JpegDecoder().startDecode(bytes);
  if (info == null) {
    throw StateError('$origin — JPEG emas yoki sarlavhasi buzuq');
  }
  final pixels = info.width * info.height;
  if (pixels == kPanoBenchWidth * kPanoBenchHeight) {
    // O'lcham to'g'ri (portret orientatsiyasi ham qabul qilinadi: dekod
    // narxi piksel soniga bog'liq, tomonlar tartibiga emas).
    return _BenchSource(bytes, info.width, info.height, origin);
  }
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) {
    throw StateError('$origin — dekodlanmadi');
  }
  final resized = img.copyResize(
    decoded,
    width: kPanoBenchWidth,
    height: kPanoBenchHeight,
    interpolation: img.Interpolation.average,
  );
  return _BenchSource(
    img.encodeJpg(resized, quality: _outQuality),
    kPanoBenchWidth,
    kPanoBenchHeight,
    '$origin+resized',
  );
}

Future<_BenchSource> _loadSource() async {
  final candidates = <String>[];
  if (_jpegPathOverride.isNotEmpty) {
    candidates.add(_jpegPathOverride);
  }
  if (Platform.isAndroid) {
    // `adb push` faqat shu papkaga ruxsatsiz yoza oladi.
    final ext = await getExternalStorageDirectory();
    if (ext != null) candidates.add('${ext.path}/$_benchFileName');
  }
  final docs = await getApplicationDocumentsDirectory();
  candidates.add('${docs.path}/$_benchFileName');

  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    return _normalize(await file.readAsBytes(), 'file:$path');
  }

  final synthetic = buildSyntheticPanoFrame();
  return _BenchSource(
    img.encodeJpg(synthetic, quality: _outQuality),
    kPanoBenchWidth,
    kPanoBenchHeight,
    'synthetic(PESSIMISTIK)',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PANOBENCH: decodeJpg / copyResize(AREA) / encodeJpg',
      (WidgetTester tester) async {
    _sampleRss();

    final source = await _loadSource();
    debugPrint('PANOBENCH_SRC src=${source.origin} '
        'w=${source.width} h=${source.height} '
        'bytes=${source.bytes.length} reps=$_reps mode=$_buildMode');
    if (!kProfileMode && !kReleaseMode) {
      debugPrint('PANOBENCH_WARN ⚠️ DEBUG (JIT) rejimi — raqamlar sof Dart '
          'uchun bir necha barobar sekin. QAROR UCHUN YAROQSIZ. '
          'Ishlatish: bash tool/pano/bench_decode.sh');
    }
    _sampleRss();

    // ── 1. decodeJpg(3840×2160) ──────────────────────────────────────────
    // Nol-takror — isitish: birinchi chaqiruvda Huffman jadvallari va
    // ichki buferlar birinchi marta ajratiladi, u tipik emas.
    img.Image? decoded;
    final decodeUs = <int>[];
    for (var i = 0; i <= _reps; i++) {
      final sw = Stopwatch()..start();
      decoded = img.decodeJpg(source.bytes);
      sw.stop();
      if (i > 0) decodeUs.add(sw.elapsedMicroseconds);
      _sampleRss();
    }
    expect(decoded, isNotNull, reason: 'manba JPEG dekodlanmadi');
    final full = decoded!;
    expect(full.width * full.height, kPanoBenchWidth * kPanoBenchHeight);

    // ── 2. copyResize(→ 702×1248, AREA) ──────────────────────────────────
    // AREA (`Interpolation.average`) — reja §4.2 dagi `cv.INTER_AREA` ning
    // eng yaqin ekvivalenti; kadr keshi aynan shu bilan tayyorlanadi.
    // Nisbat ataylab saqlanmaydi: reja §5.2 dagi kesh plitasi 702×1248
    // (portret), narx esa chiqish piksellari soniga bog'liq.
    img.Image? small;
    final resizeUs = <int>[];
    for (var i = 0; i <= _reps; i++) {
      final sw = Stopwatch()..start();
      small = img.copyResize(
        full,
        width: _cacheWidth,
        height: _cacheHeight,
        interpolation: img.Interpolation.average,
      );
      sw.stop();
      if (i > 0) resizeUs.add(sw.elapsedMicroseconds);
      _sampleRss();
    }
    expect(small!.width, _cacheWidth);

    // ── 3. encodeJpg(3072×1536, q90) ─────────────────────────────────────
    // Enkod manbai o'lchovdan TASHQARIDA tayyorlanadi.
    final canvas = img.copyResize(
      full,
      width: _outWidth,
      height: _outHeight,
      interpolation: img.Interpolation.average,
    );
    _sampleRss();
    Uint8List? encoded;
    final encodeUs = <int>[];
    for (var i = 0; i <= _reps; i++) {
      final sw = Stopwatch()..start();
      encoded = img.encodeJpg(canvas, quality: _outQuality);
      sw.stop();
      if (i > 0) encodeUs.add(sw.elapsedMicroseconds);
      _sampleRss();
    }
    expect(encoded, isNotNull);

    // ── Natija ───────────────────────────────────────────────────────────
    final decodeMs = _medianMs(decodeUs);
    debugPrint('PANOBENCH_SPREAD decodeJpg[${_spread(decodeUs)}] '
        'resizeArea[${_spread(resizeUs)}] encodeJpg[${_spread(encodeUs)}]');
    debugPrint('PANOBENCH_OUT encodedBytes=${encoded!.length}');
    debugPrint('PANOBENCH '
        'decodeJpg_ms=$decodeMs '
        'resizeArea_ms=${_medianMs(resizeUs)} '
        'encodeJpg_ms=${_medianMs(encodeUs)} '
        'peakRss_mb=${(_peakRss / (1024 * 1024)).round()}');

    // Qaror mezoni — tool/pano/README.md dagi jadval bilan bir xil.
    final verdict = decodeMs <= 1200
        ? 'sof Dart dekod QOLADI — 4-qadam O\'TKAZILADI'
        : '4-qadam MAJBURIY — native kadastr/pano_codec kanali';
    debugPrint('PANOBENCH_VERDICT decodeJpg_ms=$decodeMs chegara=1200 '
        '→ $verdict');
    debugPrint('PANOBENCH_ESTIMATE 76 kadr dekodi ≈ '
        '${(decodeMs * 76 / 1000).round()} s (1 yadro, parallelsiz)');

    // O'lchov o'zi darvoza EMAS: chegaradan o'tmagani ham QIYMATLI natija
    // (4-qadamni yoqadi). Shuning uchun test faqat o'lchov olinganini
    // tasdiqlaydi.
    expect(decodeUs.length, _reps);
    expect(resizeUs.length, _reps);
    expect(encodeUs.length, _reps);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
