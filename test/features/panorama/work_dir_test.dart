import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/stitch/raw_plane.dart';
import 'package:kadastr/features/panorama/stitch/work_dir.dart';

/// Ish papkasi va xom kadr keshi.
///
/// Bu yerdagi eng muhim da'vo — TOZALASH. Bir capture keshi ~200 MB va
/// tozalanmagan papkalar bir necha sessiyada telefonni to'ldiradi. Bu
/// hech qanday xato bilan ko'rinmaydi: foydalanuvchi «xotira yetmadi» ni
/// butunlay boshqa joyda ko'radi.
void main() {
  late Directory parent;

  setUp(() {
    parent = Directory.systemTemp.createTempSync('pano_wd_test_');
  });

  tearDown(() {
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  RawPlane plane(int w, int h, [int v = 42]) => RawPlane(
    width: w,
    height: h,
    channels: 3,
    bytes: Uint8List(w * h * 3)..fillRange(0, w * h * 3, v),
  );

  group('sampleWidthFor — manbadagi qoida', () {
    test('4K portret kadr, tuval 3072 → 701 px', () {
      // Kadr ~41° qamraydi, bu 3072 enli tuvalda ~350 piksel. Ikki
      // barobar supersampling → ~701. Reja «702» degan, farq — hisobning
      // yaxlitlanishi.
      final w = sampleWidthFor(
        frameW: 2160,
        frameH: 3840,
        longSideFovDeg: 67.3,
        canvasW: 3072,
      );
      expect(w, 701);
    });

    test('UZUN TOMON bo‘yicha FOV — orientatsiya natijani o‘zgartirmaydi', () {
      // Bu eng jim halokat: dekoder uzun tomonni almashtirsa focal 1.78×
      // xato bo'ladi va hech narsa tikilmaydi.
      final portrait = sampleWidthFor(
        frameW: 2160,
        frameH: 3840,
        longSideFovDeg: 67.3,
        canvasW: 3072,
      );
      final landscape = sampleWidthFor(
        frameW: 3840,
        frameH: 2160,
        longSideFovDeg: 67.3,
        canvasW: 3072,
      );
      // Enlar HAR XIL (kadr eni har xil), lekin ikkalasi ham o'z
      // gorizontal FOV'iga mos: landshaftda hFov kattaroq.
      expect(landscape, greaterThan(portrait));
      // Muhimi: ikkalasi ham fokusni UZUN tomondan hisoblagan, ya'ni
      // landshaft eni portret enidan aynan hFov nisbatida katta.
      expect(landscape / portrait, closeTo(67.3 / 41.04, 0.02));
    });

    test('manba enidan OSHMAYDI — 640 poli ham uni buzmaydi', () {
      // Manbada tartib `max(640, min(frameW, need))` edi va bu 320 enli
      // kadr uchun 640 qaytarardi — mavjud bo'lmagan detalni so'rash.
      // Manbada zararsiz (`_fitTo` kattalashtirmaydi), lekin qiymat
      // chaqiruvchiga qaytganda tuzoq. Manba eni eng tashqi chegara.
      expect(
        sampleWidthFor(
          frameW: 320,
          frameH: 240,
          longSideFovDeg: 67.3,
          canvasW: 8192,
        ),
        320,
      );
      // Tor FOV — pol ishlaydi, lekin manba eni yetarli.
      expect(
        sampleWidthFor(
          frameW: 4000,
          frameH: 3000,
          longSideFovDeg: 5,
          canvasW: 1024,
        ),
        640,
      );
      // Tor FOV VA kichik kadr — manba eni yutadi.
      expect(
        sampleWidthFor(
          frameW: 400,
          frameH: 300,
          longSideFovDeg: 5,
          canvasW: 1024,
        ),
        400,
      );
    });

    test('640 poli — juda tor FOV‘da ham detal qoladi', () {
      final w = sampleWidthFor(
        frameW: 4000,
        frameH: 3000,
        longSideFovDeg: 5,
        canvasW: 1024,
      );
      expect(w, 640);
    });

    test('supersampling koeffitsiyenti ta’sir qiladi', () {
      // 3072 tuvalda ×1 640 poliga tushib qolardi, shuning uchun kattaroq
      // tuval bilan o'lchanadi.
      final x1 = sampleWidthFor(
        frameW: 2160,
        frameH: 3840,
        longSideFovDeg: 67.3,
        canvasW: 6144,
        supersample: 1,
      );
      final x2 = sampleWidthFor(
        frameW: 2160,
        frameH: 3840,
        longSideFovDeg: 67.3,
        canvasW: 6144,
        supersample: 2,
      );
      expect(x1, 701);
      expect(x2, closeTo(1402, 1));
    });

    test('fitHeightFor nisbatni saqlaydi', () {
      expect(fitHeightFor(2160, 3840, 701), 1246);
      expect(fitHeightFor(3840, 2160, 1246), 701);
    });
  });

  group('cacheBytesFor', () {
    test('76 kadr 701×1246×3 ≈ 199 MB', () {
      final b = cacheBytesFor(
        width: 701,
        height: 1246,
        channels: 3,
        frameCount: 76,
      );
      expect(b / (1024 * 1024), closeTo(190, 2));
    });

    test('qo‘shimcha oktavalar ~33 % qo‘shadi', () {
      final one = cacheBytesFor(
        width: 700,
        height: 1240,
        channels: 3,
        frameCount: 1,
      );
      final three = cacheBytesFor(
        width: 700,
        height: 1240,
        channels: 3,
        frameCount: 1,
        levels: 3,
      );
      expect(three / one, closeTo(1.33, 0.02));
    });
  });

  group('create — YOLG‘IZ papka', () {
    test('papka yaratiladi va prefiks bilan nomlanadi', () async {
      final wd = await StitchWorkDir.create(parent);
      expect(wd.dir.existsSync(), isTrue);
      expect(wd.path.split('/').last, startsWith(kWorkDirPrefix));
    });

    test('ikki sessiya bir-birining keshini QAYTA YOZMAYDI', () async {
      // Foydalanuvchi birinchi tikishni tugatmasdan ikkinchisini
      // boshlasa, aralashgan kadrlardan yasalgan panorama chiqardi.
      final a = await StitchWorkDir.create(parent);
      final b = await StitchWorkDir.create(parent);
      expect(a.path, isNot(b.path));
      await a.writeCache('f1', 0, plane(2, 2, 11));
      await b.writeCache('f1', 0, plane(2, 2, 22));
      expect((await a.readCache('f1', 0))!.bytes.first, 11);
      expect((await b.readCache('f1', 0))!.bytes.first, 22);
    });
  });

  group('cachePath — fayl nomi tekshiruvi', () {
    test('`../` bo‘lgan id RAD ETILADI', () async {
      // Kadr identifikatori foydalanuvchi fayl yo'lidan kelib chiqishi
      // mumkin; tekshirilmasa ish papkasidan TASHQARIGA yozardi.
      final wd = await StitchWorkDir.create(parent);
      for (final bad in <String>['../evil', 'a/b', '..', '', 'a b', 'a.b']) {
        expect(
          () => wd.cachePath(bad, 0),
          throwsA(isA<ArgumentError>()),
          reason: '«$bad» qabul qilinmasligi kerak',
        );
      }
    });

    test('yaroqli id qabul qilinadi', () async {
      final wd = await StitchWorkDir.create(parent);
      expect(wd.cachePath('r0c12', 0), endsWith('/r0c12_l0.prw'));
      expect(wd.cachePath('A-b_9', 3), endsWith('/A-b_9_l3.prw'));
    });

    test('juda uzun id rad etiladi', () async {
      final wd = await StitchWorkDir.create(parent);
      expect(() => wd.cachePath('a' * 65, 0), throwsA(isA<ArgumentError>()));
    });

    test('daraja 0..9 bilan cheklangan', () async {
      final wd = await StitchWorkDir.create(parent);
      expect(() => wd.cachePath('a', -1), throwsA(isA<ArgumentError>()));
      expect(() => wd.cachePath('a', 10), throwsA(isA<ArgumentError>()));
    });

    test('daraja fayl nomiga tushadi — oktavalar aralashmaydi', () async {
      final wd = await StitchWorkDir.create(parent);
      await wd.writeCache('f', 0, plane(4, 4, 1));
      await wd.writeCache('f', 1, plane(2, 2, 2));
      expect((await wd.readCache('f', 0))!.width, 4);
      expect((await wd.readCache('f', 1))!.width, 2);
    });
  });

  group('write / read', () {
    test('aylanish qiymatni saqlaydi', () async {
      final wd = await StitchWorkDir.create(parent);
      await wd.writeCache('f1', 0, plane(5, 7, 200));
      final back = await wd.readCache('f1', 0);
      expect(back!.width, 5);
      expect(back.height, 7);
      expect(back.bytes.every((v) => v == 200), isTrue);
    });

    test('yozish ATOMIK — `.tmp` qolmaydi', () async {
      // Yakuniy nomda yarim fayl paydo bo'lmasligi kerak.
      final wd = await StitchWorkDir.create(parent);
      await wd.writeCache('f1', 0, plane(4, 4));
      final names = wd.dir.listSync().map((e) => e.path.split('/').last);
      expect(names, <String>['f1_l0.prw']);
      expect(names.any((n) => n.endsWith('.tmp')), isFalse);
    });

    test('QOLIB KETGAN `.tmp` keshdek o‘qilmaydi va yozishga xalal bermaydi',
        () async {
      // Oldingi sessiya yozish o'rtasida o'ldirilgan bo'lsa `.tmp`
      // qoladi. U kesh sifatida KO'RINMASLIGI va keyingi yozishni
      // to'xtatmasligi kerak.
      //
      // ⚠️ Halol chegara: `rename` ning ATOMLIGI o'zi bu testlar bilan
      // tekshirilmaydi — uzilishni yuzaga keltirish uchun fayl tizimiga
      // nosozlik kiritish kerak. Bu POSIX `rename(2)` kafolatiga
      // tayanadi. Bu yerda uning KO'RINADIGAN oqibatlari qotiriladi.
      final wd = await StitchWorkDir.create(parent);
      File('${wd.cachePath('f1', 0)}.tmp').writeAsBytesSync(
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(await wd.readCache('f1', 0), isNull, reason: '`.tmp` kesh emas');

      await wd.writeCache('f1', 0, plane(3, 3, 5));
      expect((await wd.readCache('f1', 0))!.bytes.first, 5);
      final names = wd.dir.listSync().map((e) => e.path.split('/').last);
      expect(names, <String>['f1_l0.prw'], reason: '`.tmp` qolmasligi kerak');
    });

    test('fayl YO‘Q bo‘lsa `null` — bu xato emas', () async {
      final wd = await StitchWorkDir.create(parent);
      expect(await wd.readCache('yoq', 0), isNull);
    });

    test('BUZUQ kesh o‘chiriladi va `null` qaytadi', () async {
      // Buzuq keshdan yagona chiqish yo'li — qayta dekod qilish. Uni
      // joyida qoldirish har murojaatda istisno tashlardi.
      final wd = await StitchWorkDir.create(parent);
      await wd.writeCache('f1', 0, plane(6, 6));
      final f = File(wd.cachePath('f1', 0));
      final bytes = f.readAsBytesSync();
      f.writeAsBytesSync(bytes.sublist(0, bytes.length - 20));

      expect(await wd.readCache('f1', 0), isNull);
      expect(f.existsSync(), isFalse, reason: 'buzuq fayl o‘chirilishi kerak');
      // Qayta yozish ishlaydi.
      await wd.writeCache('f1', 0, plane(6, 6, 9));
      expect((await wd.readCache('f1', 0))!.bytes.first, 9);
    });

    test('cacheBytes o‘sadi', () async {
      final wd = await StitchWorkDir.create(parent);
      expect(wd.cacheBytes(), 0);
      await wd.writeCache('f1', 0, plane(10, 10));
      expect(wd.cacheBytes(), kRawPlaneHeaderBytes + 300);
    });
  });

  group('dispose — TOZALASH MAJBURIY', () {
    test('papka va hamma fayl o‘chadi', () async {
      final wd = await StitchWorkDir.create(parent);
      await wd.writeCache('f1', 0, plane(8, 8));
      await wd.writeCache('f2', 0, plane(8, 8));
      await wd.dispose();
      expect(wd.dir.existsSync(), isFalse);
    });

    test('IKKI MARTA chaqirish xavfsiz', () async {
      // `finally` da chaqiriladi va oldin bekor qilingan bo'lishi mumkin.
      final wd = await StitchWorkDir.create(parent);
      await wd.dispose();
      await wd.dispose();
      expect(wd.dir.existsSync(), isFalse);
    });

    test('papka tashqaridan o‘chirilgan bo‘lsa ham yiqilmaydi', () async {
      final wd = await StitchWorkDir.create(parent);
      wd.dir.deleteSync(recursive: true);
      await wd.dispose();
      expect(wd.cacheBytes(), 0);
    });
  });

  group('purgeStale — eski sessiyalar qoldig‘i', () {
    test('ESKI papka o‘chadi, YANGISIGA tegilmaydi', () async {
      // Bir vaqtda ketayotgan boshqa tikishning keshini o'chirib
      // qo'ymaslik uchun yosh chegarasi bor.
      final old = Directory('${parent.path}/${kWorkDirPrefix}eski')
        ..createSync();
      final fresh = await StitchWorkDir.create(parent);

      // Soatni 7 soat oldinga surganda IKKALASI ham 6 soatdan eski
      // bo'lib qoladi — ya'ni bu test «eski o'chadi» ni tekshiradi.
      // «Yosh papkaga tegilmaydi» keyingi testda, surilmagan soat bilan.
      final n = await StitchWorkDir.purgeStale(
        parent,
        olderThan: const Duration(hours: 6),
        clock: () => DateTime.now().add(const Duration(hours: 7)),
      );
      expect(n, 2, reason: 'ikkalasi ham 6 soatdan eski hisoblanadi');
      expect(old.existsSync(), isFalse);
      expect(fresh.dir.existsSync(), isFalse);
    });

    test('YOSH papkaga TEGILMAYDI', () async {
      final wd = await StitchWorkDir.create(parent);
      final n = await StitchWorkDir.purgeStale(parent);
      expect(n, 0);
      expect(wd.dir.existsSync(), isTrue);
    });

    test('BEGONA papkalarga tegilmaydi', () async {
      // Prefiks aynan shuning uchun o'ziga xos.
      final other = Directory('${parent.path}/boshqa_narsa')..createSync();
      final f = File('${parent.path}/fayl.txt')..writeAsStringSync('x');
      await StitchWorkDir.purgeStale(
        parent,
        clock: () => DateTime.now().add(const Duration(days: 30)),
      );
      expect(other.existsSync(), isTrue);
      expect(f.existsSync(), isTrue);
    });

    test('mavjud bo‘lmagan papkada 0 qaytadi', () async {
      final gone = Directory('${parent.path}/yoq');
      expect(await StitchWorkDir.purgeStale(gone), 0);
    });
  });

  test('workDirDiagnostics hisobotga tushadigan qatorlar', () async {
    final wd = await StitchWorkDir.create(parent);
    await wd.writeCache('f1', 0, plane(4, 4));
    final d = workDirDiagnostics(wd);
    expect(d['workDir'], startsWith(kWorkDirPrefix));
    expect(d['cacheBytes'], greaterThan(0));
    // To'liq yo'l TUSHMASLIGI kerak — hisobot foydalanuvchiga ketadi.
    expect(d['workDir'].toString(), isNot(contains('/')));
  });
}
