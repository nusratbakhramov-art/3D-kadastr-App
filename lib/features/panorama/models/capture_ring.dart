/// Suratga olish rejasi — bir nuqtadan turib olinadigan ko'p qatorli halqa.
///
/// Bu fayl `panorama` loyihasidagi `lib/models/capture_ring.dart` ning porti.
/// Undagi HAMMA son O'LCHANGAN, taxmin qilinmagan — shu sababli ular aynan
/// ko'chirildi va sabablari saqlandi. Bittasini "yaxlitlash" butun qamrovni
/// buzadi.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Bitta gorizontal qator — qat'iy balandlikda.
@immutable
class CaptureRow {
  const CaptureRow({
    required this.pitchDeg,
    required this.shotCount,
    this.optional = false,
  }) : assert(shotCount >= 3);

  /// Telefon ushlanadigan balandlik, gradusda. 0 — gorizont.
  final double pitchDeg;

  final int shotCount;

  /// Shu qatorsiz ham suratga olish tugallangan hisoblanadimi.
  ///
  /// Qutb qatorlari IXTIYORIY: telefonni shiftga yoki polga tik qaratib
  /// ushlash haqiqatan noqulay. Qamrov endi PIKSELDAN o'lchanadi, ya'ni
  /// ±45 da to'xtagan capture halol 155° sfera bo'lib chiqadi — qutbi qora
  /// 180° sfera emas. Qutblar oxirgi 25° ni sotib oladi va tashlab
  /// ketilganda hech narsa turmaydi.
  final bool optional;

  double get stepDeg => 360 / shotCount;
}

/// Rejadagi bitta kadr: qaysi qator va uning qayeri.
@immutable
class ShotId {
  const ShotId(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is ShotId && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'r${row}c$column';
}

/// Bir nuqtadan turib olinadigan ko'p qatorli capture'ni rejalashtiradi va
/// kuzatadi.
///
/// Qatorlar «juda yaqin, juda yumshoq» muammosini yopadi. Bitta qator
/// vertikal bo'yicha atigi ~55° qamraydi, ya'ni ko'ruvchi ekranni to'ldirish
/// uchun tasvirni ~1.5× kattalashtirishga majbur — bu ham ko'rinishni
/// qirqadi, ham piksellarni cho'zadi. Yuqori va quyi qatorlar bandni
/// kameraning o'z 75° ko'rish burchagidan kengaytiradi va kattalashtirish
/// butunlay yo'qoladi.
///
/// Yaw kompas shimoliga emas, BIRINCHI kadrga bog'lanadi (tikilgan
/// panoramaning o'z noli baribir ixtiyoriy). Pitch'ga bog'lash kerak emas: u
/// tortishishdan olinadi, ya'ni +30 har sessiyada bir xil narsani anglatadi.
class CaptureRing {
  CaptureRing({
    this.rows = defaultRows,
    this.yawToleranceDeg = 1.5,
    this.pitchToleranceDeg = 4,
  }) : assert(rows.isNotEmpty, 'kamida bitta qator kerak'),
       assert(yawToleranceDeg > 0);

  /// Gorizont qatori ZICH, chunki ko'ruvchi vaqtining ko'p qismini o'sha
  /// bandda o'tkazadi va aynan u 360° da yopilishi shart. Tashqi qatorlar
  /// sferani vertikal cho'zish uchun — u yerda qo'polroq qadam ham yetadi:
  /// portret kadr enidan ancha baland.
  ///
  /// Qator balandliklari va nega qutblar ALOHIDA olinadi:
  ///
  /// Portret telefon kadri ~67° baland, ya'ni p balandlikdagi qator p + 33.5
  /// gacha yetadi. Demak hech qanday juft qator 90° ga yetolmaydi —
  ///
  ///     qatorlar   yetadi   qamrov    olinmagan qalpoq
  ///     0,±30      63.5     127.0     26.5
  ///     0,±40      73.5     147.0     16.5
  ///     0,±45      78.5     157.0     11.5
  ///     0,±55      88.5     177.0      1.5   (lekin qator ustma-usti 12°)
  ///
  /// — qolgani esa zenit va nadirda QORA bo'lib qaytadi. Eski 0/±30 halqasi
  /// har qutbda 26.5° ni olmasdan qoldirardi; 42 kadrli o'lchov buni 123.8°
  /// haqiqiy qamrov deb tasdiqladi.
  ///
  /// ±45 — asosiy qatorlar qo'shnisi bilan 22° ustma-ust tushib turgan holda
  /// borishi mumkin bo'lgan eng chet nuqta (feature moslashtirish shuni
  /// talab qiladi). Qolgan 11.5° qalpoqlar tik yuqoriga va tik pastga
  /// qaratib yopiladi.
  ///
  /// Qutblar ±90 da, va bu O'LCHANGAN, o'ylab topilmagan. Avval ±80 sinaldi
  /// («80 + 33.5 = 113.5 allaqachon qutbdan oshadi, yaw esa singulyarlikdan
  /// uzoqroq, mo'ljal olish oson» degan mulohaza bilan). ISHLAMAYDI: 80°
  /// dagi uchta kadr 164.7° qamrov va 3.0% qora berdi, o'sha uchta kadr 90°
  /// da esa 180.1° va 0.0%. Qutbga qaratilgan kadr uning atrofidagi diskni
  /// qamraydi va u azimut bo'yicha UZLUKSIZ; 10° yon qaragan kadr esa uzlukli
  /// dog' beradi, uchta dog' esa halqani yopmaydi.
  ///
  /// Har qutbga uch kadr, va foydalanuvchi ular orasida BURILISHI shart —
  /// qutbda yaw = roll, ya'ni burilmasdan olingan uch kadr bitta kadrning
  /// uch nusxasi. Ular qamrov emas, RO'YXATGA OLISHNI sotib oladi: ±45
  /// qatori bilan bitta emas, bir nechta har xil ustma-ustlik beradi.
  ///
  /// Gorizont qadami ustma-ustlik talab qilganidan zichroq, chunki qadam
  /// PARALLAKSNI belgilaydi. Joyida burilganda ham linza kadrdan kadrga bir
  /// necha santimetr siljiydi va yaqin obyekt qancha siljishi shu yoyga —
  /// ya'ni qadam burchagiga — proporsional. Bu ham o'lchangan: ustma-ust
  /// tushgan kadrlar orasidagi nomuvofiqlikni ular qanchalik uzoq
  /// qaratilganiga qarab guruhlasak, bitta haqiqiy capture'da 20° da 15
  /// piksel va 40° da 23, boshqasida 20° da 25 va 40° da 30 chiqadi. Ikkala
  /// egri ham yuqori uchida matcher'ning qidiruv oynasi bilan tekislangan,
  /// ya'ni haqiqiy o'sish bundan tikroq.
  ///
  /// 20° dagi ustma-ustlik allaqachon saxiy edi — kadr 53° keng. Qo'shimcha
  /// kadrlar qamrov emas, MOSLASHUV sotib oladi. 12° qadamni taxminan ikki
  /// barobar qisqartiradi va odatiy chok xatosini ham shuncha tushiradi;
  /// narxi — olinadigan va tikiladigan kadr sonining uchdan ikki barobar
  /// ortishi.
  static const List<CaptureRow> defaultRows = <CaptureRow>[
    CaptureRow(pitchDeg: 0, shotCount: 30), // har 12°
    CaptureRow(pitchDeg: 45, shotCount: 20), // har 18°
    CaptureRow(pitchDeg: -45, shotCount: 20),
    CaptureRow(pitchDeg: 90, shotCount: 3, optional: true), // zenit
    CaptureRow(pitchDeg: -90, shotCount: 3, optional: true), // nadir
  ];

  /// Shu balandlikdan keyin yaw ko'rsatkichiga ishonib bo'lmaydi.
  static const double steepPitchDeg = 70;

  /// Telefon vertikaldan qancha og'sa ham qutbda hisoblanadi.
  ///
  /// Tik yuqoriga qaratish ekrandagi raqamga qarab emas, QO'L bilan
  /// bajariladi — shuning uchun qutb qatorlari ancha bo'shroq. Ularning
  /// kadrlari shunchalik zich ustma-ust tushadiki, noaniq ushlangani ham
  /// ishlatiladigan piksel beradi.
  static const double polePitchToleranceDeg = 25;

  /// [row] qutbga qaratilganmi — u yerda yaw bilan mo'ljal olib bo'lmaydi.
  bool isPoleRow(int row) => rows[row].pitchDeg.abs() >= steepPitchDeg;

  final List<CaptureRow> rows;

  /// Kadr rejadagi yo'nalishdan qancha og'ishi mumkin.
  ///
  /// 5° edi — natijada 20° li halqa haqiqiy capture'da 15.9–24.2 oralig'ida
  /// oraliqlar bilan chiqdi (o'lchangan). Proyeksiya har kadrning O'Z qayd
  /// etilgan burchagini ishlatgani uchun bu o'z-o'zicha halokatli emas,
  /// lekin butun zaxirani yo'q qiladi: zanjirning qolgan hamma xatosi shu
  /// ustiga tushadi va qatorlar bir-biriga foydalanuvchi nima qilgan bo'lsa
  /// shunga qarab bog'lanadi.
  final double yawToleranceDeg;

  /// Balandlik esa aksincha — QATTIQ bo'lishi kerak. 12° edi, ya'ni nomiga
  /// +45 dagi qator +33 dan +57 gacha qabul qilinardi. Bu kadr balandligining
  /// chorak qismicha bo'shlik va aynan shu xato qatorlarni gorizont halqasi
  /// bilan tekislanishdan to'xtatadi.
  final double pitchToleranceDeg;

  double? _originYaw;
  final Set<ShotId> _taken = <ShotId>{};

  int get totalShots =>
      rows.fold(0, (int sum, CaptureRow r) => sum + r.shotCount);

  /// Haqiqatan olinishi SHART bo'lgan kadrlar soni.
  int get requiredShots => <int>[
    for (int i = 0; i < rows.length; i++)
      if (!rows[i].optional) rows[i].shotCount,
  ].fold(0, (int sum, int n) => sum + n);

  int get takenCount => _taken.length;

  /// Hamma MAJBURIY kadr olingach `true`. Ixtiyoriy qutb qatorlarini keyin
  /// ham qo'shish mumkin — capture ekrani suratga olishda davom etadi va
  /// «tugatish» tugmasini beradi — lekin hech narsa ularni kutmaydi.
  bool get isComplete => <ShotId>[
    for (int row = 0; row < rows.length; row++)
      if (!rows[row].optional)
        for (int c = 0; c < rows[row].shotCount; c++) ShotId(row, c),
  ].every(_taken.contains);

  /// Ixtiyoriylari bilan birga HAMMA kadr olinganda `true`.
  bool get isFullyComplete => _taken.length >= totalShots;

  bool get isAnchored => _originYaw != null;

  double get progress =>
      (_taken.length / requiredShots).clamp(0.0, 1.0).toDouble();

  bool isTaken(ShotId shot) => _taken.contains(shot);

  int takenInRow(int row) => _taken.where((ShotId s) => s.row == row).length;

  /// [from] dan [to] gacha eng qisqa ishorali burilish, -180..180.
  static double shortestTurn(double from, double to) {
    final double delta = (to - from) % 360;
    return delta > 180 ? delta - 360 : delta;
  }

  /// Telefon birinchi kadrga nisbatan qayerga qaragan, 0..360.
  double? relativeYaw(double yawDeg) {
    final double? origin = _originYaw;
    if (origin == null) return null;
    return (yawDeg - origin) % 360;
  }

  /// Telefon hozir qaysi qatorda ushlangan, yoki qatorlar orasida bo'lsa
  /// `null`.
  int? rowAt(double pitchDeg) {
    int? best;
    double bestDelta = double.infinity;
    for (int i = 0; i < rows.length; i++) {
      final double delta = (pitchDeg - rows[i].pitchDeg).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = i;
      }
    }
    if (best == null) return null;
    final double tolerance = isPoleRow(best)
        ? polePitchToleranceDeg
        : pitchToleranceDeg;
    return bestDelta <= tolerance ? best : null;
  }

  /// [shot] ning birinchi kadrga nisbatan yaw'i.
  double yawOf(ShotId shot) => shot.column * rows[shot.row].stepDeg;

  /// Hozir otilishi kerak bo'lgan kadr, yoki hech biri bo'lmasa `null`.
  ///
  /// ⚠️ To'siq [isFullyComplete], [isComplete] EMAS — va bu manbadagi
  /// XATONING TUZATILISHI.
  ///
  /// Manbada `if (isComplete) return null;` yozilgan edi. `isComplete`
  /// 70 ta MAJBURIY kadr olingach rost bo'ladi, ya'ni zatvor o'sha
  /// lahzada BUTUNLAY to'xtardi va ixtiyoriy qutb qatorlarini
  /// (`optional: true`, 6 kadr) olishning iloji QOLMASDI — foydalanuvchi
  /// gorizont va ±45 qatorlarini tugatishdan OLDIN shiftga qaragan
  /// bo'lsagina ular tushardi.
  ///
  /// Bu butun bir sinf o'lik kodni ham keltirib chiqargandi: «zenit/nadir
  /// qo'shildi» matni hech qachon chiqmasdi, `isFullyComplete` esa oddiy
  /// capture'da erishib bo'lmaydigan holat edi.
  ///
  /// [isComplete] o'z ma'nosini SAQLAYDI — u progress va «tugatish»
  /// tugmasi uchun: 70 kadrdan keyin capture yuborishga TAYYOR, lekin
  /// xohlasa davom etishi mumkin.
  ShotId? dueAt(double yawDeg, double pitchDeg) {
    if (isFullyComplete) return null;
    final int? row = rowAt(pitchDeg);
    if (row == null) return null;

    if (!isAnchored) {
      // Eng birinchi kadr GORIZONTDA bo'lishi shart: o'sha qator qolgan
      // hamma qator o'lchanadigan nolni belgilaydi va aynan u to'liq 360°
      // halqaga yopilishi kerak.
      return row == 0 ? const ShotId(0, 0) : null;
    }

    // Qutbda yaw — gimbal-lock singulyarligi va bir millimetr tebranishdan
    // keskin sakraydi, ya'ni u hech narsani nazorat qila olmaydi. Pitch esa
    // tortishishdan keladi va ishonchli qoladi, shuning uchun bu kadrlar
    // FAQAT pitch bo'yicha, ketma-ket otiladi. Foydalanuvchiga «burilishda
    // davom et» deyiladi; kadrlar qanday tushsa shunday tushadi.
    if (isPoleRow(row)) {
      for (int c = 0; c < rows[row].shotCount; c++) {
        if (!_taken.contains(ShotId(row, c))) return ShotId(row, c);
      }
      return null;
    }

    final double relative = relativeYaw(yawDeg)!;
    final CaptureRow r = rows[row];
    final int column = (relative / r.stepDeg).round() % r.shotCount;
    final ShotId shot = ShotId(row, column);
    if (_taken.contains(shot)) return null;
    return shortestTurn(relative, column * r.stepDeg).abs() <= yawToleranceDeg
        ? shot
        : null;
  }

  /// Keyingi mo'ljal: qaysi kadr, qancha burilish va qancha ko'tarish kerak.
  /// Musbat [turnDeg] — o'ngga burilish; musbat [tiltDeg] — ko'tarish.
  ({ShotId shot, double turnDeg, double tiltDeg})? nextTarget(
    double yawDeg,
    double pitchDeg,
  ) {
    // [dueAt] bilan bir xil sabab: [isComplete] da to'xtash qutb
    // qatorlarini mo'ljalsiz qoldirardi — nishon overlay ham yo'qolardi
    // va ekran «endi nima qilay» degan savolga javob bermasdi.
    if (isFullyComplete) return null;
    if (!isAnchored) {
      return (shot: const ShotId(0, 0), turnDeg: 0, tiltDeg: -pitchDeg);
    }

    final double relative = relativeYaw(yawDeg)!;
    final int? current = rowAt(pitchDeg);

    // Foydalanuvchini boshqa qatorga yuborishdan oldin u ALLAQACHON ushlab
    // turgan qatorni tugatish kerak — aks holda yo'riqnoma har tebranishda
    // qatordan qatorga sakraydi.
    final List<int> order = <int>[
      ?current,
      for (int i = 0; i < rows.length; i++)
        if (i != current) i,
    ];

    for (final int row in order) {
      ({ShotId shot, double turnDeg, double tiltDeg})? best;
      for (int column = 0; column < rows[row].shotCount; column++) {
        final ShotId shot = ShotId(row, column);
        if (_taken.contains(shot)) continue;
        final double turn = shortestTurn(relative, yawOf(shot));
        if (best == null || turn.abs() < best.turnDeg.abs()) {
          best = (
            shot: shot,
            turnDeg: turn,
            tiltDeg: rows[row].pitchDeg - pitchDeg,
          );
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  /// [shot] [yawDeg] ga qaragan holda olinganini qayd etadi.
  /// Birinchi qayd halqani bog'laydi.
  void record(ShotId shot, double yawDeg) {
    _originYaw ??= yawDeg - yawOf(shot);
    _taken.add(shot);
  }

  void reset() {
    _originYaw = null;
    _taken.clear();
  }

  /// Olingan hamma kadr, gorizont qatori birinchi.
  ///
  /// Tikish tartibi o'zi muhim emas (proyeksiya har kadrni o'z burchagiga
  /// qo'yadi), lekin halqani yopadigan qatordan boshlash diagnostikani
  /// tushunarli qiladi: nosozlik birinchi bo'lib aynan o'sha qatorda
  /// ko'rinadi.
  List<ShotId> get takenInOrder => <ShotId>[
    for (int row = 0; row < rows.length; row++)
      for (int column = 0; column < rows[row].shotCount; column++)
        if (_taken.contains(ShotId(row, column))) ShotId(row, column),
  ];

  /// [row] dagi eng katta teshik, gradusda. Ikkitadan kam kadr bo'lsa 360.
  double largestGapDeg(int row) {
    final List<int> columns = <int>[
      for (int c = 0; c < rows[row].shotCount; c++)
        if (_taken.contains(ShotId(row, c))) c,
    ];
    if (columns.length < 2) return 360;
    final double step = rows[row].stepDeg;
    double worst = 0;
    for (int i = 0; i < columns.length; i++) {
      final double gap = i == columns.length - 1
          ? 360 - (columns.last - columns.first) * step
          : (columns[i + 1] - columns[i]) * step;
      worst = math.max(worst, gap);
    }
    return worst;
  }

  /// Bundan katta teshikda qo'shni kadrlar ustma-ust tushmay qoladi va
  /// moslashtirish ularni bog'lay olmaydi.
  static const double stitchableGapDeg = 45;

  /// Faqat GORIZONT qatori yopilishi shart — tashqi qatorlar unga ustma-
  /// ustlik orqali bog'langan, ya'ni u yerdagi teshik qamrovga tushadi,
  /// butun tikishga emas.
  bool get canStitch => largestGapDeg(0) <= stitchableGapDeg;
}
