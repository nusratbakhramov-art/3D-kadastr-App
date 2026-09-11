/// Tikish ish papkasi — xom kadr keshi qayerda yashaydi.
///
/// Quvur 76 kadrni bir necha marta o'qiydi, lekin hammasini xotirada
/// ushlab turolmaydi (3.7 GB). Shu sababli har kadr bir marta dekod
/// qilinib, kichraytirilgan XOM holda shu papkaga yoziladi
/// ([RawPlane]), keyin dekodsiz qayta o'qiladi.
///
/// ⚠️ TOZALASH MAJBURIY. Bir capture keshi ~200 MB, ya'ni tozalanmagan
/// papkalar bir necha sessiyada foydalanuvchi telefonini to'ldiradi va
/// bu hech qanday xato bilan ko'rinmaydi — faqat «xotira yetmadi» bo'lib
/// chiqadi, butunlay boshqa joyda. [dispose] `finally` da chaqirilishi
/// shart, va [purgeStale] eski sessiyalarning qoldiqlarini yig'ib oladi.
library;

import 'dart:io';
import 'dart:math' as math;

import '../math/rotation.dart';
import 'raw_plane.dart';

/// Kesh papkalari nomining oldi qo'shimchasi — [purgeStale] shu bo'yicha
/// topadi. Boshqa hech narsani o'chirmasligi uchun ATAYLAB o'ziga xos.
const String kWorkDirPrefix = 'pano_stitch_';

/// Kadr uchun namuna olish eni — manbadagi `_sampleWidthFor` qoidasi.
///
/// Kadr tuval ushlab turadigan detaldan ANCHA ko'p ma'lumot olib keladi:
/// bitta kadr ~41° qamraydi, bu 3072 enli tuvalda ~350 piksel. Kadrni
/// avval `INTER_AREA` bilan kichraytirish o'sha ortiqchani O'RTACHALAB
/// yo'q qiladi; kichraytirmasdan bilinear namuna olish uni panoramaga
/// ALIASING bo'lib olib kirardi.
///
/// Koeffitsiyent 2 — ikki barobar supersampling. 640 poli: juda tor FOV'da
/// ham moslashtirish uchun yetarli detal qolishi kerak.
///
/// ⚠️ QISISH TARTIBI manbadan FARQ QILADI, ataylab. Manbada
/// `max(640, min(frameW, need))` yozilgan, ya'ni 320 piksel enli kadr
/// uchun ham 640 qaytardi — mavjud bo'lmagan detalni so'rash. Manbada bu
/// zararsiz edi, chunki `_fitTo` kattalashtirishni jimgina rad etadi
/// (`if (src.cols <= width) return src`). Bu yerda esa qiymat
/// chaqiruvchiga qaytadi va unga ishongan chaqiruvchi kadrni haqiqatan
/// kattalashtirardi — bekor ish va aliasing. Shuning uchun manba eni ENG
/// TASHQI chegara: `min(frameW, max(640, need))`. Natija manbaning
/// AMALDAGI xatti-harakati bilan bir xil, faqat tuzoq yo'q.
///
/// 4K portret kadr (2160×3840), FOV 67.3°, tuval 3072 uchun **701 px**
/// (hFov = 41.04°). Rejadagi «702» shu hisobning yaxlitlanishi.
int sampleWidthFor({
  required int frameW,
  required int frameH,
  required double longSideFovDeg,
  required int canvasW,
  int floorWidth = 640,
  double supersample = 2,
}) {
  final double focal = focalPx(frameW, frameH, longSideFovDeg);
  final double hFov = hFovDeg(frameW / 2, focal);
  final int need = (canvasW * hFov / 360 * supersample).ceil();
  return math.min(frameW, math.max(floorWidth, need));
}

/// [width] ga mos balandlik, nisbatni saqlab.
int fitHeightFor(int frameW, int frameH, int width) =>
    (frameH * width / frameW).round();

/// Bitta tikish sessiyasining ish papkasi.
class StitchWorkDir {
  StitchWorkDir._(this.dir);

  final Directory dir;

  String get path => dir.path;

  /// [parent] ichida yangi, YOLG'IZ papka yaratadi.
  ///
  /// Nom vaqt + tasodifiy qism: bir vaqtda ikki tikish ketsa (foydalanuvchi
  /// birinchisini tugatmasdan ikkinchisini boshlasa) ular bir-birining
  /// keshini QAYTA YOZMASLIGI kerak — natijada aralashgan kadrlardan
  /// yasalgan panorama chiqardi.
  static Future<StitchWorkDir> create(Directory parent) async {
    final rnd = math.Random();
    for (int attempt = 0; attempt < 8; attempt++) {
      final String name =
          '$kWorkDirPrefix${DateTime.now().millisecondsSinceEpoch}_'
          '${rnd.nextInt(1 << 32).toRadixString(36)}';
      final d = Directory('${parent.path}/$name');
      if (!d.existsSync()) {
        await d.create(recursive: true);
        return StitchWorkDir._(d);
      }
    }
    throw StateError('ish papkasi uchun bo\'sh nom topilmadi: ${parent.path}');
  }

  /// MAVJUD papkani ish papkasi sifatida oladi.
  ///
  /// Tashlab ketilgan suratga olishni tiklash uchun: kadrlar allaqachon
  /// o'sha papkada va ularni ko'chirish bekor ish bo'lardi. [create] dan
  /// farqi shundaki, bu hech narsa yaratmaydi va nomni ham tekshirmaydi
  /// — chaqiruvchi papkani qayerdan olganini biladi.
  static StitchWorkDir adopt(Directory dir) => StitchWorkDir._(dir);

  /// Kadr keshining yo'li.
  ///
  /// [frameId] fayl nomiga tushadi, shuning uchun u TEKSHIRILADI: kadr
  /// identifikatori foydalanuvchi fayl yo'lidan kelib chiqishi mumkin va
  /// `../` bo'lgan id ish papkasidan tashqariga yozardi.
  String cachePath(String frameId, int level) {
    if (frameId.isEmpty ||
        frameId.length > 64 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(frameId)) {
      throw ArgumentError.value(
        frameId,
        'frameId',
        'faqat harf, raqam, `_` va `-` (1..64) — fayl nomiga tushadi',
      );
    }
    if (level < 0 || level > 9) {
      throw ArgumentError.value(level, 'level', '0..9 bo\'lishi kerak');
    }
    return '$path/${frameId}_l$level.prw';
  }

  /// Xom kadrni keshga yozadi.
  ///
  /// ⚠️ AVVAL VAQTINCHA nomga yoziladi, keyin qayta nomlanadi. Bu
  /// atomlikni beradi: ilova yozish o'rtasida o'ldirilsa yoki disk to'lsa,
  /// yakuniy nomda YARIM fayl paydo bo'lmaydi. `RawPlane.decode` yarim
  /// faylni rad etardi, lekin uni umuman ko'rmaslik yaxshiroq — aks holda
  /// kesh «bor, lekin buzuq» holatga tushib, har murojaatda istisno
  /// tashlardi.
  Future<File> writeCache(String frameId, int level, RawPlane plane) async {
    final String finalPath = cachePath(frameId, level);
    final tmp = File('$finalPath.tmp');
    await tmp.writeAsBytes(plane.encode(), flush: true);
    return tmp.rename(finalPath);
  }

  /// Keshdan o'qiydi. Fayl yo'q bo'lsa `null` — bu XATO EMAS, shunchaki
  /// «hali dekod qilinmagan».
  ///
  /// Fayl BOR, lekin buzuq bo'lsa u o'chiriladi va `null` qaytariladi:
  /// buzuq keshdan yagona chiqish yo'li — qayta dekod qilish, va buni
  /// chaqiruvchiga yuklash har chaqiruv joyida takrorlanadigan mantiq
  /// bo'lardi.
  Future<RawPlane?> readCache(String frameId, int level) async {
    final f = File(cachePath(frameId, level));
    if (!f.existsSync()) return null;
    try {
      return RawPlane.decode(await f.readAsBytes());
    } on RawPlaneFormatException {
      try {
        await f.delete();
      } on FileSystemException {
        // O'chirib bo'lmasa ham qayta dekod qilinadi — kesh shunchaki
        // har safar rad etiladi.
      }
      return null;
    }
  }

  /// Papkani va uning hamma faylini o'chiradi. Ikki marta chaqirish
  /// XAVFSIZ — `finally` da chaqiriladi va oldin bekor qilingan bo'lishi
  /// mumkin.
  Future<void> dispose() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Tozalash NOSOZLIGI tikish natijasini bekor qilmasligi kerak:
      // panorama tayyor bo'lsa foydalanuvchi uni olishi kerak. Qoldiq
      // keyingi `purgeStale` da yig'iladi.
    }
  }

  /// Oldingi sessiyalarning qoldiq papkalarini o'chiradi.
  ///
  /// [olderThan] dan yosh papkalarga TEGILMAYDI — bir vaqtda ketayotgan
  /// boshqa tikishning keshini o'chirib qo'ymaslik uchun.
  static Future<int> purgeStale(
    Directory parent, {
    Duration olderThan = const Duration(hours: 6),
    DateTime Function() clock = DateTime.now,
  }) async {
    if (!parent.existsSync()) return 0;
    int removed = 0;
    final DateTime cutoff = clock().subtract(olderThan);
    for (final entity in parent.listSync()) {
      if (entity is! Directory) continue;
      final String name = entity.path.split('/').last;
      if (!name.startsWith(kWorkDirPrefix)) continue;
      try {
        if (entity.statSync().modified.isAfter(cutoff)) continue;
        entity.deleteSync(recursive: true);
        removed++;
      } on FileSystemException {
        // Boshqa jarayon ushlab turgan bo'lishi mumkin — keyingi safar.
      }
    }
    return removed;
  }

  /// Keshning hozirgi hajmi, baytda. Diagnostika va bo'sh disk
  /// tekshiruvi uchun.
  int cacheBytes() {
    if (!dir.existsSync()) return 0;
    int total = 0;
    for (final e in dir.listSync()) {
      if (e is File) total += e.statSync().size;
    }
    return total;
  }
}

/// Bir kadr keshi qancha joy oladi — oldindan hisoblash uchun.
///
/// 76 kadr × 701×1246 × 3 kanal ≈ **199 MB**. Bu diskda muammo emas,
/// lekin oldindan bilish kerak: iOS tomonida allaqachon 300 MB bo'sh
/// disk poli bor (`VideoCaptureRecorder.swift`) va tikish shu poldan
/// oshmasligini tekshirishi kerak.
int cacheBytesFor({
  required int width,
  required int height,
  required int channels,
  required int frameCount,
  int levels = 1,
}) {
  int perFrame = 0;
  int w = width;
  int h = height;
  for (int l = 0; l < levels; l++) {
    perFrame += kRawPlaneHeaderBytes + w * h * channels;
    w = (w + 1) >> 1;
    h = (h + 1) >> 1;
  }
  return perFrame * frameCount;
}

/// Diagnostika uchun — `report.json` ga tushadigan qatorlar.
Map<String, Object?> workDirDiagnostics(StitchWorkDir wd) =>
    <String, Object?>{
      'workDir': wd.path.split('/').last,
      'cacheBytes': wd.cacheBytes(),
    };
