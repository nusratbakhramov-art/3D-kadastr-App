import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/models/capture_ring.dart';

/// `CaptureRing` — capture rejasi.
///
/// Testlarning bir qismi mantiqni emas, O'LCHANGAN QARORLARNI qotiradi.
/// Sabab: `defaultRows` dagi har bir son haqiqiy capture'da o'lchangan va
/// "yaxlitlash" (±45 → ±40, qutbni ±90 → ±80) qamrovni jimgina buzadi —
/// natija qutbda qora dog' bo'lib chiqadi, xato esa hech qayerda
/// ko'rinmaydi. Shu sababli ular test bilan bog'langan.
void main() {
  group('defaultRows — o‘lchangan qarorlar', () {
    test('76 kadr: 30 + 20 + 20 + 3 + 3', () {
      final ring = CaptureRing();
      expect(ring.totalShots, 76);
      // Qutb qatorlari ixtiyoriy, ya'ni capture 70 kadrda tugallanadi.
      expect(ring.requiredShots, 70);
    });

    test('qadamlar: gorizont 12°, ±45 qatorlari 18°', () {
      final rows = CaptureRing.defaultRows;
      expect(rows[0].stepDeg, closeTo(12, 1e-9));
      expect(rows[1].stepDeg, closeTo(18, 1e-9));
      expect(rows[2].stepDeg, closeTo(18, 1e-9));
    });

    test('asosiy qatorlar AYNAN ±45 — ±30 emas', () {
      // ±30 halqasi 42 kadrli o'lchovda 123.8° qamrov berdi va har qutbda
      // 26.5° ni olmasdan qoldirdi. ±45 qo'shnisi bilan 22° ustma-ust
      // tushib turgan holda borish mumkin bo'lgan eng chet nuqta.
      expect(
        CaptureRing.defaultRows.map((r) => r.pitchDeg).toList(),
        <double>[0, 45, -45, 90, -90],
      );
    });

    test('qutblar AYNAN ±90 — ±80 emas', () {
      // O'LCHANGAN: 80° dagi uch kadr 164.7° qamrov va 3.0% qora berdi,
      // o'sha uch kadr 90° da 180.1° va 0.0%. Qutbga qaratilgan kadr
      // azimut bo'yicha uzluksiz disk qamraydi, 10° yon qaragani esa
      // uzlukli dog' — uch dog' halqani yopmaydi.
      final poles = CaptureRing.defaultRows.where((r) => r.optional);
      expect(poles.map((r) => r.pitchDeg.abs()).toSet(), <double>{90});
      expect(poles.map((r) => r.shotCount).toSet(), <int>{3});
    });

    test('faqat qutb qatorlari ixtiyoriy', () {
      for (final r in CaptureRing.defaultRows) {
        expect(
          r.optional,
          r.pitchDeg.abs() == 90,
          reason: '${r.pitchDeg}° qatorining ixtiyoriyligi kutilgandek emas',
        );
      }
    });

    test('tolerantliklar: yaw 1.5°, pitch 4°, qutb 25°', () {
      final ring = CaptureRing();
      // yaw 5° edi — 20° li halqa 15.9–24.2 oraliqlar bilan chiqdi.
      expect(ring.yawToleranceDeg, 1.5);
      // pitch 12° edi — nomiga +45 qator +33..+57 da qabul qilinardi.
      expect(ring.pitchToleranceDeg, 4);
      expect(CaptureRing.polePitchToleranceDeg, 25);
    });

    test('qator kamida 3 kadr talab qiladi', () {
      expect(() => CaptureRow(pitchDeg: 0, shotCount: 2), throwsA(anything));
    });
  });

  group('shortestTurn', () {
    test('halqa chetidan qisqa yo‘l bilan o‘tadi', () {
      expect(CaptureRing.shortestTurn(350, 10), closeTo(20, 1e-9));
      expect(CaptureRing.shortestTurn(10, 350), closeTo(-20, 1e-9));
    });

    test('180° chegarasida ishora almashadi', () {
      expect(CaptureRing.shortestTurn(0, 180), closeTo(180, 1e-9));
      expect(CaptureRing.shortestTurn(0, 181), closeTo(-179, 1e-9));
    });

    test('bir xil burchakda nol', () {
      expect(CaptureRing.shortestTurn(137, 137), closeTo(0, 1e-9));
    });
  });

  group('rowAt', () {
    final ring = CaptureRing();

    test('tolerantlik ichida qatorni topadi', () {
      expect(ring.rowAt(0), 0);
      expect(ring.rowAt(3.9), 0);
      expect(ring.rowAt(45), 1);
      expect(ring.rowAt(-45), 2);
    });

    test('qatorlar ORASIDA `null`', () {
      // 20° — 0 dan 20, 45 dan 25 uzoq; ikkalasi ham 4° tolerantlikdan
      // tashqarida.
      expect(ring.rowAt(20), isNull);
      expect(ring.rowAt(4.1), isNull);
    });

    test('qutb qatori ancha bo‘shroq ushlanadi', () {
      // Tik yuqoriga qaratish ekrandagi raqamga qarab bajarilmaydi.
      expect(ring.rowAt(70), 3, reason: '90-25=65, demak 70 qutbda');
      expect(ring.rowAt(-70), 4);
      expect(ring.rowAt(64), isNull, reason: '25° dan uzoq');
    });
  });

  group('dueAt', () {
    test('bog‘lanmagan halqada BIRINCHI kadr faqat gorizontda otiladi', () {
      // Gorizont qatori qolgan hamma qator o'lchanadigan nolni belgilaydi.
      final ring = CaptureRing();
      expect(ring.dueAt(123, 45), isNull, reason: '±45 dan boshlanmaydi');
      expect(ring.dueAt(123, 0), const ShotId(0, 0));
      expect(ring.isAnchored, isFalse, reason: '`dueAt` bog‘lamaydi');
    });

    test('birinchi qayddan keyin halqa bog‘lanadi', () {
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 123);
      expect(ring.isAnchored, isTrue);
      expect(ring.relativeYaw(123), closeTo(0, 1e-9));
      expect(ring.relativeYaw(135), closeTo(12, 1e-9));
    });

    test('yaw tolerantligidan tashqarida otilmaydi', () {
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 0);
      // 12° — 1-ustunning aynan markazi.
      expect(ring.dueAt(12, 0), const ShotId(0, 1));
      // 1.5° dan tashqari.
      expect(ring.dueAt(14, 0), isNull);
      expect(ring.dueAt(13.4, 0), const ShotId(0, 1));
    });

    test('olingan kadr qayta otilmaydi', () {
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 0);
      expect(ring.dueAt(0, 0), isNull);
    });

    test('qutb kadrlari FAQAT pitch bo‘yicha ketma-ket otiladi', () {
      // Qutbda yaw gimbal-lock singulyarligi — bir millimetr tebranishdan
      // sakraydi, ya'ni hech narsani nazorat qila olmaydi.
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 0);
      expect(ring.dueAt(37, 90), const ShotId(3, 0));
      ring.record(const ShotId(3, 0), 37);
      // Yaw butunlay boshqa, lekin keyingi qutb kadri baribir tayyor.
      expect(ring.dueAt(211, 90), const ShotId(3, 1));
      ring.record(const ShotId(3, 1), 211);
      ring.record(const ShotId(3, 2), 300);
      expect(ring.dueAt(0, 90), isNull, reason: 'qutb qatori tugadi');
    });

    test('MAJBURIY kadrlar tugagach QUTB kadrlari hali otiladi', () {
      // ⚠️ MANBADAGI XATONING TESTI. Manbada to'siq `isComplete` edi,
      // ya'ni 70 kadrdan keyin zatvor BUTUNLAY to'xtardi va ixtiyoriy
      // qutb qatorlarini olishning iloji qolmasdi.
      final ring = _filledRequired();
      expect(ring.isComplete, isTrue, reason: 'majburiylari tugadi');
      expect(ring.isFullyComplete, isFalse, reason: 'qutblar qoldi');

      // Zenitga qaratilsa kadr hali ham so'raladi.
      expect(ring.dueAt(0, 90), const ShotId(3, 0));
      expect(ring.nextTarget(0, 90), isNotNull);
    });

    test('HAMMA kadr tugagach hech narsa otilmaydi', () {
      final ring = _filledRequired();
      for (final r in <int>[3, 4]) {
        for (var c = 0; c < 3; c++) {
          ring.record(ShotId(r, c), c * 120);
        }
      }
      expect(ring.isFullyComplete, isTrue);
      expect(ring.dueAt(0, 90), isNull);
      expect(ring.nextTarget(0, 90), isNull);
      expect(ring.dueAt(0, 0), isNull);
    });
  });

  group('nextTarget', () {
    test('bog‘lanmaganda gorizontga qaytaradi', () {
      final ring = CaptureRing();
      final t = ring.nextTarget(50, 30)!;
      expect(t.shot, const ShotId(0, 0));
      expect(t.turnDeg, 0);
      expect(t.tiltDeg, closeTo(-30, 1e-9), reason: '30° dan 0 ga tushirish');
    });

    test('foydalanuvchi USHLAB turgan qatorni avval tugatadi', () {
      // Aks holda yo'riqnoma har tebranishda qatordan qatorga sakraydi.
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 0);
      // Gorizontda turibmiz va gorizontda olinmagan kadr bor — mo'ljal
      // ±45 ga (u yerda ham hammasi bo'sh) o'tib ketmasligi kerak.
      expect(ring.nextTarget(0, 0)!.shot.row, 0);
      // ±45 da turganda esa o'sha qator afzal.
      expect(ring.nextTarget(0, 45)!.shot.row, 1);
    });

    test('qatorlar orasida turganda ham mo‘ljal beradi', () {
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 0);
      // `rowAt(20)` null — mo'ljal shunda ham topilishi kerak, aks holda
      // foydalanuvchi qatorlar orasida qolib ketardi.
      final t = ring.nextTarget(0, 20);
      expect(t, isNotNull);
    });

    test('eng yaqin burilishni tanlaydi', () {
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 0);
      // 30° da turibmiz: 2-ustun (24°) 3-ustundan (36°) yaqinroq emas —
      // ikkalasi ham 6°. Muhimi: tanlangan burilish |6°| dan oshmasligi.
      expect(ring.nextTarget(30, 0)!.turnDeg.abs(), lessThanOrEqualTo(6.001));
    });
  });

  group('largestGapDeg / canStitch', () {
    test('ikkitadan kam kadrda 360', () {
      final ring = CaptureRing();
      expect(ring.largestGapDeg(0), 360);
      ring.record(const ShotId(0, 0), 0);
      expect(ring.largestGapDeg(0), 360);
    });

    test('o‘rash teshigi ham hisoblanadi', () {
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 0);
      ring.record(const ShotId(0, 1), 12);
      // 0 va 1 orasida 12°, qolgan aylanada 348°.
      expect(ring.largestGapDeg(0), closeTo(348, 1e-9));
    });

    test('to‘liq qatorda teshik bitta qadam', () {
      final ring = CaptureRing();
      for (int c = 0; c < 30; c++) {
        ring.record(ShotId(0, c), c * 12);
      }
      expect(ring.largestGapDeg(0), closeTo(12, 1e-9));
      expect(ring.canStitch, isTrue);
    });

    test('canStitch FAQAT gorizont qatoriga qaraydi', () {
      // Tashqi qatorlar gorizontga ustma-ustlik orqali bog'langan — u
      // yerdagi teshik qamrovga tushadi, butun tikishga emas.
      final ring = CaptureRing();
      for (int c = 0; c < 30; c++) {
        ring.record(ShotId(0, c), c * 12);
      }
      expect(ring.takenInRow(1), 0, reason: '±45 butunlay bo‘sh');
      expect(ring.canStitch, isTrue);
    });

    test('45° dan katta teshik tikilmaydi', () {
      final ring = CaptureRing();
      // Har 5-ustun → 60° qadam.
      for (int c = 0; c < 30; c += 5) {
        ring.record(ShotId(0, c), c * 12);
      }
      expect(ring.largestGapDeg(0), greaterThan(CaptureRing.stitchableGapDeg));
      expect(ring.canStitch, isFalse);
    });
  });

  group('holat', () {
    test('isComplete ixtiyoriy qatorlarni KUTMAYDI', () {
      final ring = _filledRequired();
      expect(ring.isComplete, isTrue);
      expect(ring.isFullyComplete, isFalse);
      expect(ring.takenCount, 70);
    });

    test('progress majburiy kadrlarga nisbatan va 1.0 da to‘xtaydi', () {
      final ring = _filledRequired();
      expect(ring.progress, closeTo(1.0, 1e-9));
      ring.record(const ShotId(3, 0), 0);
      expect(ring.progress, 1.0, reason: 'qutblar 100% dan oshirmaydi');
    });

    test('takenInOrder gorizontdan boshlanadi', () {
      final ring = CaptureRing();
      ring.record(const ShotId(1, 5), 90);
      ring.record(const ShotId(0, 3), 36);
      expect(ring.takenInOrder.first.row, 0);
      expect(ring.takenInOrder, <ShotId>[
        const ShotId(0, 3),
        const ShotId(1, 5),
      ]);
    });

    test('reset bog‘lanishni ham bo‘shatadi', () {
      final ring = CaptureRing();
      ring.record(const ShotId(0, 0), 123);
      ring.reset();
      expect(ring.isAnchored, isFalse);
      expect(ring.takenCount, 0);
      expect(ring.relativeYaw(0), isNull);
    });

    test('ShotId qiymat bo‘yicha tenglashadi', () {
      // `_taken` — `Set<ShotId>`, ya'ni `==`/`hashCode` buzilsa butun
      // hisob buziladi va hech qachon tugamaydigan capture chiqadi.
      expect(const ShotId(1, 2), const ShotId(1, 2));
      expect(const ShotId(1, 2).hashCode, const ShotId(1, 2).hashCode);
      expect(const ShotId(1, 2), isNot(const ShotId(2, 1)));
      // To'plam ALOHIDA yasalgan ikki nusxani bittaga qo'shishi kerak.
      // Ataylab ijro vaqtida yasaladi: literal ichidagi takror `const`
      // nusxa analizatorning `equal_elements_in_set` ogohlantirishini
      // chiqaradi va aslida hech narsani sinamaydi.
      final Set<ShotId> ids = <ShotId>{};
      for (int i = 0; i < 2; i++) {
        ids.add(ShotId(1, 2));
      }
      expect(ids, hasLength(1));
    });
  });
}

/// Hamma MAJBURIY kadr olingan halqa.
CaptureRing _filledRequired() {
  final ring = CaptureRing();
  final rows = CaptureRing.defaultRows;
  for (int r = 0; r < rows.length; r++) {
    if (rows[r].optional) continue;
    for (int c = 0; c < rows[r].shotCount; c++) {
      ring.record(ShotId(r, c), c * rows[r].stepDeg);
    }
  }
  return ring;
}
