// 3-qadam (MIL-0) uchun sintetik 3840×2160 JPEG generatori.
//
// NEGA KERAK: benchmark (`integration_test/pano_decode_bench_test.dart`)
// telefonda 4K JPEG dekod qiladi, lekin qurilmada tayyor kadr har doim ham
// bo'lavermaydi. Shu skript bittasini yasab beradi.
//
// ⚠️ SINTETIK KADR — PESSIMISTIK O'LCHOV.
//   Bu yerdagi rasm ataylab shovqinli (har pikselga ±grain) va qirralarga
//   boy. JPEG dekod vaqti Huffman'da qancha nol bo'lmagan koeffitsiyent
//   borligiga to'g'ridan-to'g'ri bog'liq: shovqin ularni ko'paytiradi, ya'ni
//   fayl KATTA va dekod SEKIN chiqadi. Haqiqiy kamera kadri (ayniqsa
//   osmon/devor kabi tekis joylari bor kadr) bundan TEZROQ dekodlanadi.
//
//   Ya'ni: shu fayl bilan olingan raqam yuqori chegara. «≤ 1200 ms»
//   mezonidan O'TSA — qaror ishonchli. YIQILSA — haqiqiy foto bilan qayta
//   o'lchash SHART, chunki sintetika 1.3–2× jarima qo'shgan bo'lishi mumkin.
//
// Ishlatish:
//   dart run tool/pano/gen_test_jpeg.dart /tmp/pano_bench.jpg
//   dart run tool/pano/gen_test_jpeg.dart /tmp/kichik.jpg 1920 1080
//
// `print` shu faylda ATAYLAB — bu CLI skript, chiqish kanali shu.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Benchmark kadrining standart o'lchami — `sensor_stitcher` kutgan 4K.
const int kPanoBenchWidth = 3840;
const int kPanoBenchHeight = 2160;

/// Sintetik kadrni yasaydi. `seed` qotirilgan — bir xil chiqish, ya'ni
/// takroriy o'lchovlar solishtiriladigan bo'lib qoladi.
///
/// Manzara ataylab "ko'cha" ga o'xshatilgan: osmon gradienti, binolar va
/// deraza panjarasi (qirralar), yo'l tekstura si — ustiga donadorlik.
/// Tekis rangli katta maydon (masalan bir tusli fon) JPEG'ni sun'iy ravishda
/// tez dekodlanadigan qilib qo'yardi va o'lchov yolg'on optimistik chiqardi.
img.Image buildSyntheticPanoFrame({
  int width = kPanoBenchWidth,
  int height = kPanoBenchHeight,
  int seed = 20260910,
}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  // To'g'ridan-to'g'ri buferga yozamiz: `setPixelRgb` 8.3 M marta chaqirilsa
  // generator o'zi bir necha barobar sekinlashadi.
  final buf = image.toUint8List();
  final rnd = math.Random(seed);

  final horizon = (height * 0.46).round();
  // Binolar: kenglik bo'ylab turli balandlikdagi bloklar.
  final blockWidth = math.max(1, width ~/ 24);
  final blockTop = List<int>.generate(
    width ~/ blockWidth + 1,
    (i) => (horizon * (0.18 + 0.62 * rnd.nextDouble())).round(),
  );

  var o = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      int r;
      int g;
      int b;
      if (y < horizon) {
        final top = blockTop[x ~/ blockWidth];
        if (y >= top) {
          // Bino: kulrang fasad + deraza panjarasi (qirralar manbai).
          final base = 96 + (x ~/ blockWidth) % 5 * 11;
          final window = ((x % 46) < 26) && ((y % 62) < 34);
          final v = window ? base + 74 : base;
          r = v;
          g = v + 4;
          b = v + 12;
        } else {
          // Osmon: yuqoridan pastga och tortadigan gradient.
          final t = y / horizon;
          r = (66 + 130 * t).round();
          g = (108 + 122 * t).round();
          b = (168 + 78 * t).round();
        }
      } else {
        // Yo'l: perspektiv bo'yicha qorayadi + ko'ndalang chiziqlar.
        final t = (y - horizon) / (height - horizon);
        final v = (128 - 46 * t).round();
        final stripe = ((x + (y * 3)) % 230) < 8 ? 58 : 0;
        r = v + stripe;
        g = v + stripe;
        b = v - 6 + stripe;
      }
      // Donadorlik — JPEG'ni "haqiqiy foto" kabi og'ir qiladi (yuqoridagi
      // ogohlantirishga qarang: aslida undan ham og'ir).
      final n = rnd.nextInt(25) - 12;
      buf[o++] = _clamp8(r + n);
      buf[o++] = _clamp8(g + n);
      buf[o++] = _clamp8(b + n);
    }
  }
  return image;
}

int _clamp8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    print('Ishlatish: dart run tool/pano/gen_test_jpeg.dart <out.jpg> '
        '[width] [height]');
    exit(args.isEmpty ? 2 : 0);
  }
  final out = args[0];
  final width = args.length > 1 ? int.parse(args[1]) : kPanoBenchWidth;
  final height = args.length > 2 ? int.parse(args[2]) : kPanoBenchHeight;

  final sw = Stopwatch()..start();
  final image = buildSyntheticPanoFrame(width: width, height: height);
  final drawMs = sw.elapsedMilliseconds;

  sw.reset();
  // q=90 — benchmarkdagi chiqish sifati bilan bir xil, ya'ni fayl kattaligi
  // ham o'sha tartibda bo'ladi.
  final jpeg = img.encodeJpg(image, quality: 90);
  final encodeMs = sw.elapsedMilliseconds;

  final file = File(out);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(jpeg);

  print('yozildi : $out');
  print('o\'lcham : ${width}x$height');
  print('hajm    : ${jpeg.length} bayt '
      '(${(jpeg.length / (1024 * 1024)).toStringAsFixed(2)} MB)');
  print('vaqt    : chizish $drawMs ms, enkod $encodeMs ms (host, JIT)');
  print('');
  print('⚠️ Sintetik shovqin JPEG dekodini SEKINLASHTIRADI — bu fayl bilan');
  print('   olingan raqam PESSIMISTIK. Iloji bo\'lsa haqiqiy 4K foto ishlating.');
}
