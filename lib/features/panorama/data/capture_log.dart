/// Suratga olish yozuvi — burchaklar DISKKA, har kadrdan keyin.
///
/// NEGA BU BOR (manbadagi `0dac253`, qurilmadan olingan holat). 70 kadrli
/// suratga olish tikishga ketdi, tikish daqiqalab davom etdi, foydalanuvchi
/// «qotib qoldi» deb ilovani yopdi. Hech narsa qulamagan: iOS shunchaki
/// protsessor uzoq band bo'lganini qayd etgan. Lekin burchaklar suratga
/// olish OXIRIDA yozilardi, ya'ni voz kechish ularning HAMMASINI yo'qotdi
/// — diskda 70 ta yaroqli surat qoldi va ularning qayerga qaratilgani
/// haqida hech narsa qolmadi.
///
/// ⚠️ Bizda bu manbadagidan YOMONROQ chiqardi: manbada hech bo'lmasa
/// qayta tikish ekrani bor edi, bizda u yo'q. Burchaklar yo'qolsa
/// suratlar butunlay yetim qoladi.
///
/// Ikki qatlam himoya:
///
///  1. [CaptureLog.write] — har kadrdan keyin butun fayl qayta yoziladi.
///     70 ta kichik yozuv daqiqalarga yoyilgan holda o'lchanadigan narxga
///     ega emas, va har kadr OLINGAN ZAHOTI xavfsiz bo'ladi;
///  2. [shotsFromNames] — yozuv baribir yo'q bo'lsa, burchaklar fayl
///     NOMLARIDAN tiklanadi: halqa har faylni o'zi mo'ljallangan nishon
///     nomi bilan ataydi.
library;

import 'dart:convert';
import 'dart:io';

import '../models/capture_ring.dart';
import '../models/sensor_shot.dart';
import '../stitch/work_dir.dart';

/// Yozuv fayli — ish papkasining ichida, kadrlar yonida.
const String kCaptureLogName = 'aims.json';

/// Kadrlar papkasi (ish papkasi ichida).
const String kShotsDirName = 'shots';

/// Kadr fayli qanday nomlanadi.
///
/// ⚠️ YAGONA MANBA. Yozuvchi va [shotsFromNames] AYNI shu qoidani
/// ishlatishi shart: tiklovchi boshqa naqsh kutsa, u hech narsa topmaydi
/// va JIM turadi — xato bermaydi, shunchaki nol kadr qaytaradi.
/// `capture_log_test.dart` ikkalasini bog'laydi.
///
/// Nol bilan to'ldirilgan ustun raqami fayl tartibi olish tartibiga mos
/// kelishi uchun: `c02` `c10` dan keyin turmasligi kerak.
String shotFileName(ShotId shot) =>
    'shot_r${shot.row}c${shot.column.toString().padLeft(2, '0')}.jpg';

/// [shotFileName] ning teskarisi — nomdan `(qator, ustun)`.
final RegExp _namePattern = RegExp(r'^shot_r(\d+)c(\d+)\.jpg$');

/// Tiklangan burchaklar QAYERDAN kelgani.
enum AimSource {
  /// Suratga olish paytida yozilgan — aniq.
  recorded,

  /// Fayl nomlaridan qayta qurilgan — taxminiy.
  filenames,
}

/// Tashlab ketilgan suratga olish.
class StrandedCapture {
  const StrandedCapture({
    required this.dir,
    required this.shots,
    required this.source,
  });

  /// Ish papkasi — tikish shu yerda davom etadi.
  final Directory dir;

  final List<SensorShot> shots;

  final AimSource source;
}

/// Ish papkasidagi burchaklar yozuvi.
class CaptureLog {
  CaptureLog(this.dir);

  /// Ish papkasi (kadrlar `shots/` ichida).
  final Directory dir;

  File get file => File('${dir.path}/$kCaptureLogName');

  /// Burchaklarni yozadi — HAR KADRDAN KEYIN chaqiriladi.
  ///
  /// ⚠️ SINXRON va BUTUN FAYL. Ikkalasi ham ataylab:
  ///
  /// * sinxron — yozuv diskka tushgan bo'lishi kerak, `await` esa uni
  ///   jarayon o'lgan paytda uchayotgan holda qoldirishi mumkin;
  /// * butun fayl — yozuv har yozishdan keyin YAROQLI JSON bo'lishi
  ///   shart. Qo'shib borish yarim yozilgan faylni qoldiradi, ya'ni
  ///   endi parse bo'lmaydigan faylni — butun maqsad esa aynan ixtiyoriy
  ///   lahzada uzilishdan omon qolish.
  ///
  /// Yozuv YIQILMAYDI: diskka yoza olmaslik — suratga olishni to'xtatish
  /// uchun sabab emas. Kadrlar baribir diskda va [shotsFromNames] ularni
  /// tiklay oladi.
  void write(List<SensorShot> shots, {bool clockwisePositive = true}) {
    final Map<String, Object?> record = <String, Object?>{
      'version': 1,
      // Yaw qaysi tomonga o'sishi. `HeadingSource.clockwisePositive`
      // bayrog'i qachondir almashsa, ALLAQACHON olingan sessiyalar eski
      // kelishuvda yozilgan bo'ladi va ularni yangi kelishuvda tikish
      // panoramani KO'ZGUGA aylantirardi. Yozib qo'yish ikki qator, uni
      // keyin qayta tiklab bo'lmaydi.
      'yawConvention': clockwisePositive ? 'clockwise' : 'counterClockwise',
      'writtenAt': DateTime.now().toIso8601String(),
      'shotCount': shots.length,
      'shots': <Map<String, Object?>>[
        for (final SensorShot s in shots)
          <String, Object?>{
            // ⚠️ FAQAT fayl nomi, to'liq yo'l EMAS. iOS ilovaning
            // hujjatlar papkasini yangilanish va qayta o'rnatishda
            // BOSHQA yo'lga ko'chiradi, ya'ni saqlangan mutlaq yo'l
            // keyingi ochilishda mavjud bo'lmagan joyga ko'rsatardi.
            'file': s.path.split('/').last,
            'yawDeg': s.yawDeg,
            'pitchDeg': s.pitchDeg,
            'rollDeg': s.rollDeg,
            'row': s.row,
          },
      ],
    };

    try {
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(record),
        flush: true,
      );
    } on FileSystemException {
      // Yozib bo'lmadi — suratga olish DAVOM ETADI. Fayl nomlaridan
      // tiklash yo'li ochiq qoladi.
    }
  }

  /// Yozuvni o'qiydi. Fayl yo'q, buzuq yoki bo'sh bo'lsa — bo'sh ro'yxat.
  ///
  /// Yo'llar `dir` ga nisbatan QAYTA yig'iladi (yuqoridagi iOS sababi),
  /// va diskda yo'q kadr tashlab ketiladi: yozuv bor-u fayl yo'q bo'lishi
  /// mumkin (foydalanuvchi joy bo'shatgan), va yo'q faylni tikuvchiga
  /// berish uni «o'qib bo'lmadi» deb sanashga majbur qilardi.
  List<SensorShot> read() {
    final Directory shotsDir = Directory('${dir.path}/$kShotsDirName');
    final Object? decoded;
    try {
      if (!file.existsSync()) return const <SensorShot>[];
      decoded = jsonDecode(file.readAsStringSync());
    } on FileSystemException {
      return const <SensorShot>[];
    } on FormatException {
      // Yarim yozilgan yoki buzilgan fayl — nomlardan tiklash qoladi.
      return const <SensorShot>[];
    }

    if (decoded is! Map<String, Object?>) return const <SensorShot>[];
    final Object? raw = decoded['shots'];
    if (raw is! List) return const <SensorShot>[];

    final double yawSign = decoded['yawConvention'] == 'counterClockwise'
        ? -1
        : 1;

    final out = <SensorShot>[];
    for (final Object? e in raw) {
      if (e is! Map<String, Object?>) continue;
      final Object? name = e['file'];
      if (name is! String || name.isEmpty) continue;
      final String path = '${shotsDir.path}/$name';
      if (!File(path).existsSync()) continue;
      out.add(
        SensorShot(
          path: path,
          yawDeg: ((e['yawDeg'] as num?)?.toDouble() ?? 0) * yawSign,
          pitchDeg: (e['pitchDeg'] as num?)?.toDouble() ?? 0,
          rollDeg: (e['rollDeg'] as num?)?.toDouble() ?? 0,
          row: (e['row'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return out;
  }
}

/// Burchaklarni fayl NOMLARIDAN qayta quradi.
///
/// Kadrlar diskda-yu, yozuv yo'q bo'lgan holat uchun — burchaklarni
/// yozishga ulgurmasdan uzilgan suratga olish. Ilgari bu capture
/// yo'qolgani degani edi: 70 ta surat, va ularning birortasi qayerga
/// qaratilganini biladigan hech narsa yo'q. Halqa har faylni o'zi
/// mo'ljallangan nishon nomi bilan ataydi, ya'ni `shot_r0c12.jpg` va
/// halqa geometriyasi burchakni QAYTARIB BERADI.
///
/// TAXMINIY: zatvor halqaning bag'rikengligi ichida ixtiyoriy joyda
/// ochiladi, aynan nishon ustida emas — ya'ni bu burchaklar bir-ikki
/// gradus xato. Yo'qotilgan capture bilan solishtirganda bu hech narsa.
///
/// ⚠️ QADAM SHU QATORDA HAQIQATAN NECHTA USTUN BORLIGIDAN olinadi,
/// ilovaning HOZIRGI zichligidan emas. 20 gradusda olingan eski sessiya
/// aks holda 12 gradusda olingandek qayta qurilardi — har kadr o'z
/// o'rnidan uzoqlashib boradigan panorama.
List<SensorShot> shotsFromNames(
  List<File> files, {
  List<CaptureRow> rows = CaptureRing.defaultRows,
}) {
  final byRow = <int, List<(int, File)>>{};
  for (final File f in files) {
    final RegExpMatch? m = _namePattern.firstMatch(f.path.split('/').last);
    if (m == null) continue;
    (byRow[int.parse(m.group(1)!)] ??= <(int, File)>[]).add((
      int.parse(m.group(2)!),
      f,
    ));
  }

  final out = <SensorShot>[];
  for (final MapEntry<int, List<(int, File)>> e in byRow.entries) {
    int highest = 0;
    for (final (int column, File _) in e.value) {
      if (column > highest) highest = column;
    }
    final double step = 360 / (highest + 1);
    // Qator indeksi hozirgi rejadan tashqarida bo'lsa — balandlik
    // noma'lum. Nol — gorizont, ya'ni eng kam zarar keltiradigan taxmin.
    final double pitch = e.key < rows.length ? rows[e.key].pitchDeg : 0;
    for (final (int column, File file) in e.value) {
      out.add(
        SensorShot(
          path: file.path,
          yawDeg: column * step,
          pitchDeg: pitch,
          row: e.key,
        ),
      );
    }
  }
  return out;
}

/// Kadrlari qolib ketgan, lekin tugallanmagan suratga olishni topadi.
///
/// [parent] ichidagi panorama ish papkalari ko'riladi va eng YANGISI
/// qaytariladi. [exclude] — hozirgi sessiya papkasi, u tabiiyki
/// «tashlab ketilgan» emas.
///
/// Avval yozuv o'qiladi; u bo'sh bo'lsa fayl nomlaridan tiklanadi.
/// Ikkalasi ham bo'sh bo'lsa papka o'tkazib yuboriladi — kadrsiz papka
/// tiklashga arzimaydi.
///
/// ⚠️ [StitchWorkDir.purgeStale] dan KEYIN chaqirilsin: aks holda bu
/// allaqachon eskirgan, o'chirilishi kerak bo'lgan papkani taklif
/// qilardi.
Future<StrandedCapture?> findStranded(
  Directory parent, {
  Directory? exclude,
  int minShots = 2,
}) async {
  if (!parent.existsSync()) return null;

  final candidates = <Directory>[];
  await for (final FileSystemEntity e in parent.list(followLinks: false)) {
    if (e is! Directory) continue;
    final String name = e.path.split('/').last;
    if (!name.startsWith(kWorkDirPrefix)) continue;
    if (exclude != null && e.path == exclude.path) continue;
    candidates.add(e);
  }
  // Nom vaqt belgisi bilan boshlanadi, ya'ni teskari alifbo tartibi —
  // yangisidan eskisiga.
  candidates.sort((Directory a, Directory b) => b.path.compareTo(a.path));

  for (final Directory d in candidates) {
    final List<SensorShot> recorded = CaptureLog(d).read();
    if (recorded.length >= minShots) {
      return StrandedCapture(
        dir: d,
        shots: recorded,
        source: AimSource.recorded,
      );
    }

    final Directory shotsDir = Directory('${d.path}/$kShotsDirName');
    if (!shotsDir.existsSync()) continue;
    final List<File> files = shotsDir
        .listSync(followLinks: false)
        .whereType<File>()
        .toList();
    final List<SensorShot> rebuilt = shotsFromNames(files);
    if (rebuilt.length >= minShots) {
      return StrandedCapture(
        dir: d,
        shots: rebuilt,
        source: AimSource.filenames,
      );
    }
  }
  return null;
}
