/// Haqiqiy kadr yuklovchisi — JPEG → kichraytirilgan PLANAR xom bufer.
///
/// [FrameLoader] ning ishlab chiqarish amalga oshirilishi. Testlar sun'iy
/// yuklovchi ishlatadi, chunki bu yerdagi dekod og'ir va sekin — MIL-0
/// benchmarki aynan shu narxni o'lchaydi.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'dart_stitcher.dart';
import 'raw_plane.dart';
import 'work_dir.dart';

/// Fayl o'qishni almashtirish uchun — testda diskka tegmasdan sinash.
typedef ReadBytes = Future<Uint8List?> Function(String path);

/// Dekoderni almashtirish uchun.
///
/// NEGA KERAK. EXIF orientatsiyasini sinash uchun ORIENTATSIYA TEGI BOR
/// JPEG kerak, lekin `img.encodeJpg` tegni O'ZI qo'llab yozadi — ya'ni
/// shu kutubxona bilan bunday faylni yasab bo'lmaydi (o'lchandi:
/// 80×40 + orientation=6 → 40×80, tegsiz). Haqiqiy kamera fayllari esa
/// tegni SAQLAYDI. Dekoderni almashtirish quvurdagi eng halokatli
/// nosozlikni haqiqiy foto talab qilmasdan sinash imkonini beradi.
typedef DecodeImage = img.Image? Function(Uint8List bytes);

img.Image? _defaultDecode(Uint8List bytes) => img.decodeImage(bytes);

class ImageFrameLoader implements FrameLoader {
  ImageFrameLoader({
    required this.workDir,
    required this.canvasW,
    required this.longSideFovDeg,
    required this.readBytes,
    this.level = 0,
    this.decode = _defaultDecode,
  });

  final StitchWorkDir workDir;
  final int canvasW;
  final double longSideFovDeg;
  final ReadBytes readBytes;
  final DecodeImage decode;

  /// Oktava darajasi — kesh fayli nomiga tushadi.
  final int level;

  /// Nechta kadr keshdan olindi. Diagnostika uchun: ikkinchi o'tishda bu
  /// son kadrlar soniga teng bo'lishi kerak, aks holda kesh ishlamayapti
  /// va har o'tish qayta dekod qilyapti.
  int cacheHits = 0;
  int decoded = 0;

  @override
  Future<RawPlane?> load(String path, int targetWidth) async {
    final String id = frameIdFor(path);

    // 1. Kesh. Butun yondashuv shunga tayanadi: JPEG bir marta dekod
    //    qilinadi, quvur esa har kadrga bir necha marta qaytadi.
    final cached = await workDir.readCache(id, level);
    if (cached != null) {
      cacheHits++;
      return cached;
    }

    final bytes = await readBytes(path);
    if (bytes == null) return null;

    img.Image? decodedImage;
    try {
      decodedImage = decode(bytes);
    } catch (_) {
      // Buzuq JPEG butun capture'ni yo'qotmasligi kerak — chaqiruvchi
      // `null` ni «shu kadr o'tkazib yuborildi» deb qabul qiladi.
      return null;
    }
    if (decodedImage == null) return null;

    // 2. ⚠️ EXIF ORIENTATSIYASI — rejadagi ENG JIM VA ENG HALOKATLI farq
    //    (§4.2). `cv.imread` uni AVTOMATIK qo'llaydi. Qo'llanmasa
    //    portret kadr landshaft bo'lib o'qiladi, `focalPx` uzun tomonni
    //    almashtirib ~1.78× xato beradi va HECH NARSA tikilmaydi —
    //    hech qanday xato chiqmasdan.
    //
    //    `copyResize` buni o'zi ham chaqiradi, LEKIN faqat masshtablash
    //    bo'lganda. Kadr allaqachon kerakli o'lchamda bo'lsa
    //    masshtablash o'tkazib yuboriladi va orientatsiya QO'LLANMAY
    //    qoladi. Shuning uchun bu yerda OCHIQ chaqiriladi.
    var image = img.bakeOrientation(decodedImage);

    // 3. Kichraytirish. Kadr tuval ushlay oladigan detaldan ancha ko'p
    //    ma'lumot olib keladi; `average` (≈ `INTER_AREA`) o'sha
    //    ortiqchani O'RTACHALAB yo'q qiladi. Bilinear namuna olish uni
    //    panoramaga ALIASING bo'lib olib kirardi.
    final int want = targetWidth > 0
        ? targetWidth
        : sampleWidthFor(
            frameW: image.width,
            frameH: image.height,
            longSideFovDeg: longSideFovDeg,
            canvasW: canvasW,
          );
    if (want < image.width) {
      image = img.copyResize(
        image,
        width: want,
        height: fitHeightFor(image.width, image.height, want),
        interpolation: img.Interpolation.average,
      );
    }

    final plane = toPlanar(image);
    decoded++;
    // Yozish nosozligi (disk to'ldi) tikishni TO'XTATMAYDI — kesh
    // tezlik uchun, to'g'rilik uchun emas.
    try {
      await workDir.writeCache(id, level, plane);
    } catch (_) {
      // Keyingi murojaat qayta dekod qiladi.
    }
    return plane;
  }
}

/// Fayl yo'lidan kesh identifikatorini yasaydi.
///
/// `cachePath` faqat `[A-Za-z0-9_-]` qabul qiladi (yo'l chiqishining
/// oldini olish uchun), fayl nomlari esa nuqta va bo'sh joy saqlaydi.
/// Shu sababli nom TOZALANADI va oxiriga to'liq yo'lning xeshi
/// qo'shiladi — ikki xil papkadagi bir xil nomli kadrlar bir-birini
/// qayta yozmasligi uchun.
String frameIdFor(String path) {
  final base = path.split('/').last;
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final h = path.hashCode.toUnsigned(32).toRadixString(36);
  final head = safe.length > 40 ? safe.substring(safe.length - 40) : safe;
  return '${head}_$h';
}

/// `img.Image` → PLANAR `RawPlane` (RGB).
///
/// `package:image` piksellarni INTERLEAVED saqlaydi; butun raster
/// qatlami esa planar ishlaydi. Konvertatsiya shu yerda, bir marta.
RawPlane toPlanar(img.Image image) {
  final int w = image.width;
  final int h = image.height;
  final int n = w * h;
  final bytes = Uint8List(n * 3);
  int i = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      bytes[i] = p.r.toInt();
      bytes[n + i] = p.g.toInt();
      bytes[2 * n + i] = p.b.toInt();
      i++;
    }
  }
  return RawPlane(width: w, height: h, channels: 3, bytes: bytes);
}
