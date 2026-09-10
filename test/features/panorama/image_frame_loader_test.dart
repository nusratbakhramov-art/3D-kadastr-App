import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kadastr/features/panorama/stitch/image_frame_loader.dart';
import 'package:kadastr/features/panorama/stitch/work_dir.dart';

/// Haqiqiy kadr yuklovchisi.
///
/// Eng muhim test — EXIF ORIENTATSIYASI. Bu rejadagi (§4.2) eng jim va
/// eng halokatli farq: `cv.imread` orientatsiyani avtomatik qo'llaydi,
/// Dart dekoderi esa yo'q. Qo'llanmasa portret kadr landshaft bo'lib
/// o'qiladi, `focalPx` uzun tomonni almashtirib ~1.78× xato beradi va
/// HECH NARSA tikilmaydi — hech qanday xato chiqmasdan.
void main() {
  late Directory parent;
  setUp(() => parent = Directory.systemTemp.createTempSync('pano_ifl_'));
  tearDown(() {
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  /// Portret (tik) JPEG: kengligi 40, balandligi 80.
  /// [orientation] berilsa EXIF tegi qo'yiladi.
  Uint8List makeJpeg(int w, int h, {int? orientation}) {
    final im = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        im.setPixelRgb(x, y, (x * 6) % 256, (y * 3) % 256, 90);
      }
    }
    if (orientation != null) im.exif.imageIfd.orientation = orientation;
    return img.encodeJpg(im, quality: 95);
  }

  Future<ImageFrameLoader> loaderFor(
    Map<String, Uint8List?> files, {
    int canvasW = 512,
  }) async => ImageFrameLoader(
    workDir: await StitchWorkDir.create(parent),
    canvasW: canvasW,
    longSideFovDeg: 67.3,
    readBytes: (p) async => files[p],
  );

  /// Orientatsiya TEGI BOR tasvir qaytaradigan dekoder.
  ///
  /// ⚠️ `img.encodeJpg` tegni O'ZI qo'llab yozadi (o'lchandi: 80×40 +
  /// orientation=6 → 40×80, tegsiz), ya'ni shu kutubxona bilan bunday
  /// JPEG yasab bo'lmaydi. Haqiqiy kamera fayllari esa tegni SAQLAYDI —
  /// shu sababli dekoder almashtiriladi.
  DecodeImage taggedDecoder(int w, int h, int orientation) => (_) {
    final im = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        im.setPixelRgb(x, y, (x * 6) % 256, (y * 3) % 256, 90);
      }
    }
    im.exif.imageIfd.orientation = orientation;
    return im;
  };

  Future<ImageFrameLoader> taggedLoader(
    int w,
    int h,
    int orientation, {
    int canvasW = 512,
  }) async => ImageFrameLoader(
    workDir: await StitchWorkDir.create(parent),
    canvasW: canvasW,
    longSideFovDeg: 67.3,
    readBytes: (_) async => Uint8List(8),
    decode: taggedDecoder(w, h, orientation),
  );

  group('EXIF orientatsiyasi', () {
    test('orientation=6 UZUN TOMONNI almashtiradi', () {
      // 6 = «90° soat yo'nalishi bo'yicha burilgan». Bu eng keng
      // tarqalgan holat: telefon portretda olgan foto ko'p qurilmada
      // aynan shunday saqlanadi — piksellar landshaft, teg esa
      // «buring» deydi.
      final raw = taggedDecoder(80, 40, 6)(Uint8List(0))!;
      expect(raw.width, 80, reason: 'xom piksellar landshaft');
      final baked = img.bakeOrientation(raw);
      expect(baked.width, 40, reason: 'orientatsiyadan keyin portret');
      expect(baked.height, 80);
    });

    test('yuklovchi orientatsiyani QO‘LLAYDI', () async {
      // Qo'llanmasa 80×40 (landshaft) qaytardi va `focalPx` uzun
      // tomonni almashtirib ~1.78× xato berardi — HECH NARSA
      // tikilmasdi, hech qanday xato chiqmasdan.
      final l = await taggedLoader(80, 40, 6);
      final plane = (await l.load('a.jpg', 0))!;
      expect(plane.height, greaterThan(plane.width), reason: 'portret bo‘lsin');
    });

    test('orientation YO‘Q bo‘lsa tasvir o‘zgarmaydi', () async {
      final l = await loaderFor(<String, Uint8List?>{
        'a.jpg': makeJpeg(40, 80),
      });
      final plane = (await l.load('a.jpg', 0))!;
      expect(plane.width, 40);
      expect(plane.height, 80);
    });

    test('KICHRAYTIRISH bo‘lmaganda ham qo‘llanadi', () async {
      // `copyResize` orientatsiyani o'zi ham chaqiradi, LEKIN faqat
      // masshtablash bo'lganda. Kadr allaqachon kerakli o'lchamda
      // bo'lsa u o'tkazib yuboriladi — shuning uchun yuklovchi uni
      // OCHIQ chaqiradi.
      final l = await taggedLoader(80, 40, 6, canvasW: 8192);
      final plane = (await l.load('a.jpg', 0))!;
      expect(plane.width, 40, reason: 'masshtablashsiz ham burilsin');
      expect(plane.height, 80);
    });

    test('boshqa orientatsiya qiymatlari ham qo‘llanadi', () async {
      // 8 = 270°. 3 = 180° (o'lcham o'zgarmaydi, lekin piksellar
      // aylanadi).
      expect((await (await taggedLoader(80, 40, 8)).load('a', 0))!.width, 40);
      final flat = (await (await taggedLoader(80, 40, 3)).load('a', 0))!;
      expect(flat.width, 80, reason: '180° o‘lchamni o‘zgartirmaydi');
    });
  });

  test('kichraytirish O‘RTACHALAYDI — nearest EMAS', () async {
    // Kadr tuval ushlay oladigan detaldan ANCHA ko'p ma'lumot olib
    // keladi. `average` (≈ `INTER_AREA`) o'sha ortiqchani o'rtachalab
    // yo'q qiladi; `nearest` esa uni panoramaga ALIASING bo'lib olib
    // kirardi — mayda naqsh (g'isht, kafel, parket) tikilgan
    // panoramada mavj bo'lib chiqadi.
    //
    // Shaxmat naqshi: o'rtachalab kichraytirilsa o'rta kulrang
    // chiqadi, nearest bilan esa sof qora/oq qoladi.
    const w = 64, h = 64;
    final board = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = (x + y).isEven ? 0 : 255;
        board.setPixelRgb(x, y, v, v, v);
      }
    }
    final l = ImageFrameLoader(
      workDir: await StitchWorkDir.create(parent),
      canvasW: 512,
      longSideFovDeg: 67.3,
      readBytes: (_) async => Uint8List(8),
      decode: (_) => board,
    );
    final plane = (await l.load('a.jpg', 16))!;
    expect(plane.width, 16, reason: '4× kichraytirilsin');
    final vals = plane.plane(0);
    final extreme = vals.where((v) => v < 40 || v > 215).length;
    expect(
      extreme / vals.length,
      lessThan(0.2),
      reason: 'o‘rtachalanmagan — nearest ishlatilgan',
    );
  });

  group('kesh', () {
    test('ikkinchi murojaat KESHDAN keladi', () async {
      // Butun yondashuv shunga tayanadi: JPEG bir marta dekod
      // qilinadi, quvur esa har kadrga bir necha marta qaytadi.
      final l = await loaderFor(<String, Uint8List?>{
        'a.jpg': makeJpeg(60, 90),
      });
      final first = (await l.load('a.jpg', 0))!;
      expect(l.decoded, 1);
      expect(l.cacheHits, 0);

      final second = (await l.load('a.jpg', 0))!;
      expect(l.decoded, 1, reason: 'qayta dekod qilinmasin');
      expect(l.cacheHits, 1);
      expect(second.bytes, first.bytes);
      expect(second.width, first.width);
    });

    test('har oktava ALOHIDA keshlanadi', () async {
      final wd = await StitchWorkDir.create(parent);
      final files = <String, Uint8List?>{'a.jpg': makeJpeg(60, 90)};
      ImageFrameLoader at(int level) => ImageFrameLoader(
        workDir: wd,
        canvasW: 512,
        longSideFovDeg: 67.3,
        readBytes: (p) async => files[p],
        level: level,
      );
      await at(0).load('a.jpg', 0);
      final l1 = at(1);
      await l1.load('a.jpg', 0);
      expect(l1.cacheHits, 0, reason: '1-oktava alohida keshda');
      expect(l1.decoded, 1);
    });

    test('kesh yozib bo‘lmasa ham natija QAYTADI', () async {
      // Disk to'lganda tikish TO'XTAMASLIGI kerak — kesh tezlik uchun,
      // to'g'rilik uchun emas.
      final wd = await StitchWorkDir.create(parent);
      final l = ImageFrameLoader(
        workDir: wd,
        canvasW: 512,
        longSideFovDeg: 67.3,
        readBytes: (p) async => makeJpeg(60, 90),
      );
      await wd.dispose(); // papka yo'q → yozish yiqiladi
      final plane = await l.load('a.jpg', 0);
      expect(plane, isNotNull);
      expect(plane!.width, greaterThan(0));
    });
  });

  group('nosozliklar', () {
    test('fayl YO‘Q bo‘lsa `null`', () async {
      final l = await loaderFor(<String, Uint8List?>{});
      expect(await l.load('yoq.jpg', 0), isNull);
    });

    test('BUZUQ JPEG butun capture‘ni yo‘qotmaydi', () async {
      final l = await loaderFor(<String, Uint8List?>{
        'bad.jpg': Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      });
      expect(await l.load('bad.jpg', 0), isNull);
    });
  });

  group('frameIdFor', () {
    test('xavfsiz belgilar — `cachePath` qabul qiladi', () async {
      final wd = await StitchWorkDir.create(parent);
      for (final p in <String>[
        '/a/b/IMG 001.jpg',
        '../../etc/passwd',
        '/x/y/kadr.r0c12.jpeg',
        'ЯЯЯ.jpg',
      ]) {
        expect(() => wd.cachePath(frameIdFor(p), 0), returnsNormally);
      }
    });

    test('bir xil NOMLI, boshqa YO‘LLI kadrlar ajratiladi', () async {
      // Aks holda ikki papkadagi `IMG_0001.jpg` bir-birini qayta
      // yozardi va panorama takrorlangan kadrdan yasalardi.
      expect(frameIdFor('/a/IMG_1.jpg'), isNot(frameIdFor('/b/IMG_1.jpg')));
    });

    test('bir xil yo‘l bir xil id beradi', () {
      expect(frameIdFor('/a/IMG_1.jpg'), frameIdFor('/a/IMG_1.jpg'));
    });

    test('juda uzun nom qisqartiriladi', () async {
      final wd = await StitchWorkDir.create(parent);
      final id = frameIdFor('/x/${'a' * 300}.jpg');
      expect(id.length, lessThanOrEqualTo(64));
      expect(() => wd.cachePath(id, 0), returnsNormally);
    });
  });

  test('toPlanar kanallarni AJRATADI', () {
    final im = img.Image(width: 2, height: 1);
    im.setPixelRgb(0, 0, 10, 20, 30);
    im.setPixelRgb(1, 0, 40, 50, 60);
    final p = toPlanar(im);
    expect(p.plane(0), Uint8List.fromList([10, 40]));
    expect(p.plane(1), Uint8List.fromList([20, 50]));
    expect(p.plane(2), Uint8List.fromList([30, 60]));
  });
}
