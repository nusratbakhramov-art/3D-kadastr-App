import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/data/capture_log.dart';
import 'package:kadastr/features/panorama/models/capture_ring.dart';
import 'package:kadastr/features/panorama/models/sensor_shot.dart';
import 'package:kadastr/features/panorama/stitch/work_dir.dart';

/// Suratga olish yozuvi — «capture hech qachon yo'qolmasin».
///
/// Manbadagi `0dac253` porti. Qo'riqlanadigan narsa bitta: kadrlar
/// diskda bo'lsa, ularning burchaklari ham QAYTARIB OLINADI — yozuvdan
/// yoki, u yo'q bo'lsa, fayl nomlaridan.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('pano_log_test'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Ish papkasi + ichida kadr fayllari.
  Directory workDirWith(List<ShotId> shots, {String name = '${kWorkDirPrefix}1'}) {
    final Directory d = Directory('${root.path}/$name')
      ..createSync(recursive: true);
    final Directory s = Directory('${d.path}/$kShotsDirName')
      ..createSync(recursive: true);
    for (final ShotId id in shots) {
      File('${s.path}/${shotFileName(id)}').writeAsBytesSync(<int>[0xFF, 0xD8]);
    }
    return d;
  }

  List<SensorShot> sensorShots(Directory wd, List<ShotId> ids) => <SensorShot>[
    for (int i = 0; i < ids.length; i++)
      SensorShot(
        path: '${wd.path}/$kShotsDirName/${shotFileName(ids[i])}',
        yawDeg: i * 12.0,
        pitchDeg: 0,
        rollDeg: 1.5,
        row: ids[i].row,
      ),
  ];

  group('shotFileName — YAGONA manba', () {
    test('nol bilan to‘ldiriladi, ya‘ni tartib to‘g‘ri', () {
      expect(shotFileName(const ShotId(0, 2)), 'shot_r0c02.jpg');
      expect(shotFileName(const ShotId(0, 10)), 'shot_r0c10.jpg');
      // Alifbo tartibi olish tartibiga MOS kelishi kerak.
      final names = <String>[
        for (int c = 0; c < 12; c++) shotFileName(ShotId(0, c)),
      ];
      expect(names.toList()..sort(), names);
    });

    test('YOZUVCHI va TIKLOVCHI bir xil qoidani ishlatadi', () {
      // Eng muhim bog'lanish. Tiklovchi boshqa naqsh kutsa u XATO
      // BERMAYDI — shunchaki nol kadr qaytaradi va capture jimgina
      // yo'qoladi.
      final Directory wd = workDirWith(<ShotId>[
        const ShotId(0, 0),
        const ShotId(0, 7),
        const ShotId(1, 3),
      ]);
      final List<File> files = Directory('${wd.path}/$kShotsDirName')
          .listSync()
          .whereType<File>()
          .toList();

      expect(shotsFromNames(files).length, 3);
    });
  });

  group('yozuv — yozish va o‘qish', () {
    test('aylanma yo‘l: yozilgan burchaklar QAYTIB keladi', () {
      final ids = <ShotId>[const ShotId(0, 0), const ShotId(0, 1)];
      final Directory wd = workDirWith(ids);
      final List<SensorShot> written = sensorShots(wd, ids);

      CaptureLog(wd).write(written);
      final List<SensorShot> back = CaptureLog(wd).read();

      expect(back.length, 2);
      expect(back[0].yawDeg, 0);
      expect(back[1].yawDeg, 12);
      expect(back[1].rollDeg, 1.5);
      expect(back[1].path, written[1].path);
    });

    test('MUTLAQ yo‘l saqlanmaydi — papka ko‘chsa ham topiladi', () {
      // iOS ilova papkasini yangilanishda BOSHQA yo'lga ko'chiradi.
      // Yozuvda mutlaq yo'l qolsa, keyingi ochilishda u mavjud
      // bo'lmagan joyga ko'rsatardi.
      final ids = <ShotId>[const ShotId(0, 0)];
      final Directory wd = workDirWith(ids);
      CaptureLog(wd).write(sensorShots(wd, ids));

      final String raw = File('${wd.path}/$kCaptureLogName').readAsStringSync();
      expect(raw.contains(root.path), isFalse, reason: 'mutlaq yo‘l yozilgan');
      expect(raw.contains('shot_r0c00.jpg'), isTrue);
    });

    test('HAR YOZISHDAN KEYIN yaroqli JSON', () {
      // Butun maqsad — ixtiyoriy lahzada uzilishdan omon qolish. Qo'shib
      // borилsa yarim yozilgan fayl endi parse bo'lmasdi.
      final ids = <ShotId>[const ShotId(0, 0), const ShotId(0, 1)];
      final Directory wd = workDirWith(ids);
      final log = CaptureLog(wd);

      for (int n = 1; n <= ids.length; n++) {
        log.write(sensorShots(wd, ids.sublist(0, n)));
        final Object? parsed = jsonDecode(log.file.readAsStringSync());
        expect(parsed, isA<Map<String, Object?>>());
        expect((parsed! as Map<String, Object?>)['shotCount'], n);
      }
    });

    test('diskda YO‘Q kadr o‘qishda tashlab ketiladi', () {
      final ids = <ShotId>[const ShotId(0, 0), const ShotId(0, 1)];
      final Directory wd = workDirWith(ids);
      CaptureLog(wd).write(sensorShots(wd, ids));

      File('${wd.path}/$kShotsDirName/${shotFileName(ids[1])}').deleteSync();
      expect(CaptureLog(wd).read().length, 1);
    });

    test('buzuq yoki yo‘q fayl — YIQILMAYDI, bo‘sh qaytadi', () {
      final Directory wd = workDirWith(<ShotId>[const ShotId(0, 0)]);
      expect(CaptureLog(wd).read(), isEmpty);

      File('${wd.path}/$kCaptureLogName').writeAsStringSync('{"shots": [');
      expect(CaptureLog(wd).read(), isEmpty);
    });

    test('yaw KELISHUVI yozuvdan o‘qiladi', () {
      // Bayroq qachondir almashsa, eski sessiyalar eski kelishuvda
      // yozilgan bo'ladi va ularni yangisida tikish panoramani
      // KO'ZGUGA aylantirardi.
      const ShotId id = ShotId(0, 3);
      final Directory wd = workDirWith(<ShotId>[id]);
      // ⚠️ Yaw NOLDAN farqli bo'lishi shart: `-0.0 == 0.0`, ya'ni
      // belgini nol ustida sinash hech narsani tekshirmasdi.
      final shot = SensorShot(
        path: '${wd.path}/$kShotsDirName/${shotFileName(id)}',
        yawDeg: 36,
        pitchDeg: 0,
      );

      CaptureLog(wd).write(<SensorShot>[shot], clockwisePositive: false);
      expect(CaptureLog(wd).read().single.yawDeg, -36);

      CaptureLog(wd).write(<SensorShot>[shot]);
      expect(CaptureLog(wd).read().single.yawDeg, 36);
    });
  });

  group('shotsFromNames — yozuvsiz tiklash', () {
    test('QADAM shu qatorda nechta ustun borligidan olinadi', () {
      // ⚠️ Ilovaning HOZIRGI zichligidan emas. 20 gradusda olingan
      // sessiya 12 gradusda olingandek qayta qurilsa, har kadr o'z
      // o'rnidan uzoqlashib boradi.
      final Directory wd = workDirWith(<ShotId>[
        for (int c = 0; c < 18; c++) ShotId(0, c), // 360/18 = 20°
      ]);
      final List<File> files = Directory('${wd.path}/$kShotsDirName')
          .listSync()
          .whereType<File>()
          .toList();

      final List<SensorShot> out = shotsFromNames(files)
        ..sort((a, b) => a.yawDeg.compareTo(b.yawDeg));

      expect(out.length, 18);
      expect(out[1].yawDeg, 20, reason: 'qadam hozirgi 12° dan olingan');
      expect(out.last.yawDeg, 340);
    });

    test('balandlik QATOR rejasidan keladi', () {
      final Directory wd = workDirWith(<ShotId>[
        const ShotId(0, 0),
        const ShotId(1, 0),
        const ShotId(2, 0),
      ]);
      final List<File> files = Directory('${wd.path}/$kShotsDirName')
          .listSync()
          .whereType<File>()
          .toList();

      final Map<int, double> pitch = <int, double>{
        for (final SensorShot s in shotsFromNames(files)) s.row: s.pitchDeg,
      };
      expect(pitch[0], CaptureRing.defaultRows[0].pitchDeg);
      expect(pitch[1], CaptureRing.defaultRows[1].pitchDeg);
      expect(pitch[2], CaptureRing.defaultRows[2].pitchDeg);
    });

    test('rejadan tashqaridagi qator — gorizont deb olinadi', () {
      final Directory wd = workDirWith(<ShotId>[const ShotId(99, 0)]);
      final List<File> files = Directory('${wd.path}/$kShotsDirName')
          .listSync()
          .whereType<File>()
          .toList();
      expect(shotsFromNames(files).single.pitchDeg, 0);
    });

    test('begona fayllar e‘tiborga OLINMAYDI', () {
      final Directory wd = workDirWith(<ShotId>[const ShotId(0, 0)]);
      File('${wd.path}/$kShotsDirName/panorama.jpg').writeAsStringSync('x');
      File('${wd.path}/$kShotsDirName/.DS_Store').writeAsStringSync('x');

      final List<File> files = Directory('${wd.path}/$kShotsDirName')
          .listSync()
          .whereType<File>()
          .toList();
      expect(shotsFromNames(files).length, 1);
    });
  });

  group('findStranded — tashlab ketilganini topish', () {
    test('yozuv bor — ANIQ burchaklar', () async {
      final ids = <ShotId>[const ShotId(0, 0), const ShotId(0, 1)];
      final Directory wd = workDirWith(ids);
      CaptureLog(wd).write(sensorShots(wd, ids));

      final StrandedCapture? found = await findStranded(root);
      expect(found, isNotNull);
      expect(found!.source, AimSource.recorded);
      expect(found.shots.length, 2);
    });

    test('yozuv YO‘Q — fayl nomlaridan, va buni AYTADI', () async {
      workDirWith(<ShotId>[
        const ShotId(0, 0),
        const ShotId(0, 1),
        const ShotId(0, 2),
      ]);

      final StrandedCapture? found = await findStranded(root);
      expect(found, isNotNull);
      // Manba TAXMINIY ekani yo'qolmasligi kerak — foydalanuvchiga shu
      // asosda boshqacha matn ko'rsatiladi.
      expect(found!.source, AimSource.filenames);
      expect(found.shots.length, 3);
    });

    test('HOZIRGI sessiya taklif qilinmaydi', () async {
      final ids = <ShotId>[const ShotId(0, 0), const ShotId(0, 1)];
      final Directory wd = workDirWith(ids);
      CaptureLog(wd).write(sensorShots(wd, ids));

      expect(await findStranded(root, exclude: wd), isNull);
    });

    test('kadri kam papka taklif qilinmaydi', () async {
      workDirWith(<ShotId>[const ShotId(0, 0)]);
      expect(await findStranded(root), isNull);
    });

    test('panorama papkasi BO‘LMAGAN joyga tegmaydi', () async {
      final Directory other = Directory('${root.path}/boshqa_papka')
        ..createSync();
      Directory('${other.path}/$kShotsDirName').createSync();
      for (int c = 0; c < 5; c++) {
        File(
          '${other.path}/$kShotsDirName/${shotFileName(ShotId(0, c))}',
        ).writeAsStringSync('x');
      }
      expect(await findStranded(root), isNull);
    });

    test('bir nechta bo‘lsa ENG YANGISI', () async {
      workDirWith(<ShotId>[
        const ShotId(0, 0),
        const ShotId(0, 1),
      ], name: '${kWorkDirPrefix}100_a');
      workDirWith(<ShotId>[
        const ShotId(0, 0),
        const ShotId(0, 1),
        const ShotId(0, 2),
      ], name: '${kWorkDirPrefix}900_b');

      final StrandedCapture? found = await findStranded(root);
      expect(found!.shots.length, 3, reason: 'eskisi tanlandi');
    });

    test('bo‘sh ildiz — null, yiqilmaydi', () async {
      expect(await findStranded(Directory('${root.path}/yo_q')), isNull);
      expect(await findStranded(root), isNull);
    });
  });
}
