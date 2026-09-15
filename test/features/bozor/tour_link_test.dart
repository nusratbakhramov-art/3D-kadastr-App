import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/models/tour_link.dart';

/// 360° house tour havolalari — sof mantiq.
///
/// Bu yerdagi hamma xato JIM: tur «buzilgan» bo'lib ko'rinmaydi,
/// shunchaki tugma bosilganda hech qayerga olib bormaydi yoki umuman
/// chizilmaydi. Shuning uchun har qoida aniq misol bilan qotirilgan.
void main() {
  const String p1 = '/data/shot1.jpg';
  const String p2 = '/data/shot2.jpg';
  const String p3 = '/data/shot3.jpg';
  const String k1 = 'listings/media/7/k1.jpg';
  const String k2 = 'listings/media/7/k2.jpg';

  TourLink link(String from, String to, {double yaw = 0, double pitch = 0}) =>
      TourLink(from: from, to: to, yawDeg: yaw, pitchDeg: pitch);

  group('resolveTourLinks — yuborishga tayyorlash', () {
    test('lokal yo‘llar S3 kalitiga o‘giriladi', () {
      final out = resolveTourLinks(
        <TourLink>[link(p1, p2, yaw: 90, pitch: -5)],
        uploaded: <String, String>{p1: k1, p2: k2},
        allowedKeys: <String>{k1, k2},
      );
      expect(out, hasLength(1));
      expect(out.single['from_key'], k1);
      expect(out.single['to_key'], k2);
      expect(out.single['yaw_deg'], 90);
      expect(out.single['pitch_deg'], -5);
    });

    test('ALLAQACHON kalit bo‘lgan havola o‘zgarmaydi', () {
      // Tahrirlash oqimi: e'londa turgan panoramalar kalit bilan keladi.
      final out = resolveTourLinks(
        <TourLink>[link(k1, k2)],
        uploaded: const <String, String>{},
        allowedKeys: <String>{k1, k2},
      );
      expect(out.single['from_key'], k1);
      expect(out.single['to_key'], k2);
    });

    test('YUBORILAYOTGAN media‘da yo‘q panorama TASHLANADI', () {
      // ⚠️ Butun sabab shu. Server havolani o'sha so'rovdagi media bilan
      // solishtiradi; ro'yxatga tushmagan panoramaga ishora qilgan
      // havola 400 beradi va BUTUN e'lon yuborilmay qolardi — bitta
      // tugma uchun.
      final out = resolveTourLinks(
        <TourLink>[link(p1, p2)],
        uploaded: <String, String>{p1: k1, p2: k2},
        // `k2` ro'yxatda YO'Q — masalan uning yuklanishi uzilgan.
        allowedKeys: <String>{k1},
      );
      expect(out, isEmpty);
    });

    test('YUKLANMAGAN panorama TASHLANADI', () {
      final out = resolveTourLinks(
        <TourLink>[link(p1, p2)],
        uploaded: <String, String>{p1: k1},
        allowedKeys: <String>{k1},
      );
      expect(out, isEmpty);
    });

    test('o‘ziga havola TASHLANADI', () {
      // Ikki lokal yo'l bitta kalitga tushishi mumkin (bir fayl ikki
      // marta tanlangan) — o'shanda havola o'ziga aylanadi.
      final out = resolveTourLinks(
        <TourLink>[link(p1, p2)],
        uploaded: <String, String>{p1: k1, p2: k1},
        allowedKeys: <String>{k1},
      );
      expect(out, isEmpty);
    });

    test('TAKRORIY juftlik bir marta ketadi', () {
      // Server takrorni rad etadi (unikal indeks), ya'ni ikkinchisini
      // yuborish butun e'lonni yiqitardi.
      final out = resolveTourLinks(
        <TourLink>[link(p1, p2, yaw: 10), link(p1, p2, yaw: 200)],
        uploaded: <String, String>{p1: k1, p2: k2},
        allowedKeys: <String>{k1, k2},
      );
      expect(out, hasLength(1));
      expect(out.single['yaw_deg'], 10, reason: 'birinchisi saqlanadi');
    });

    test('IKKI YO‘NALISH saqlanadi', () {
      final out = resolveTourLinks(
        <TourLink>[link(p1, p2), link(p2, p1)],
        uploaded: <String, String>{p1: k1, p2: k2},
        allowedKeys: <String>{k1, k2},
      );
      expect(out, hasLength(2));
    });

    test('yaw 0..360 ga keltiriladi, pitch qisiladi', () {
      final out = resolveTourLinks(
        <TourLink>[link(p1, p2, yaw: 725, pitch: 140)],
        uploaded: <String, String>{p1: k1, p2: k2},
        allowedKeys: <String>{k1, k2},
      );
      expect(out.single['yaw_deg'], 5);
      expect(out.single['pitch_deg'], 90);
    });

    test('bo‘sh ro‘yxat — bo‘sh natija', () {
      expect(
        resolveTourLinks(
          const <TourLink>[],
          uploaded: const <String, String>{},
          allowedKeys: const <String>{},
        ),
        isEmpty,
      );
    });
  });

  group('danglingLinks — yetim havolalar', () {
    test('o‘chirilgan panoramaga ishora qilgani topiladi', () {
      final links = <TourLink>[link(p1, p2), link(p1, p3)];
      expect(danglingLinks(links, <String>[p1, p2]), <TourLink>[link(p1, p3)]);
    });

    test('hammasi joyida bo‘lsa bo‘sh', () {
      expect(danglingLinks(<TourLink>[link(p1, p2)], <String>[p1, p2]), isEmpty);
    });
  });

  group('reachableFrom / unreachablePanoramas', () {
    test('zanjir bo‘ylab yuriladi', () {
      final links = <TourLink>[link(p1, p2), link(p2, p3)];
      expect(reachableFrom(p1, links), <String>{p1, p2, p3});
    });

    test('havola YO‘NALTIRILGAN — teskarisi bepul emas', () {
      // A→B qo'ygan foydalanuvchi B→A ni ham qo'yishi kerak, aks holda
      // xaridor xonaga kirib QAYTA OLMAYDI.
      expect(reachableFrom(p2, <TourLink>[link(p1, p2)]), <String>{p2});
    });

    test('yetib bo‘lmaydigan panorama topiladi', () {
      expect(
        unreachablePanoramas(<String>[p1, p2, p3], <TourLink>[link(p1, p2)]),
        <String>[p3],
      );
    });

    test('halqa cheksiz aylanmaydi', () {
      // A→B→A — eng oddiy tur, va sodda yurish uni cheksiz qilardi.
      final links = <TourLink>[link(p1, p2), link(p2, p1)];
      expect(reachableFrom(p1, links), <String>{p1, p2});
    });

    test('bitta panorama — ogohlantirish YO‘Q', () {
      expect(unreachablePanoramas(<String>[p1], const <TourLink>[]), isEmpty);
    });
  });

  group('angularSeparationDeg — tugmalar ustma-ust tushmasin', () {
    test('bir xil yo‘nalish — nol', () {
      // ⚠️ Bardosh 1e-9 EMAS: `acos` argumenti 1 ga yaqinlashganda
      // aniqlikni yo'qotadi va bir xil ikki yo'nalish uchun ~9e-7
      // gradus chiqadi. Bu funksiya 12° chegarasi uchun ishlaydi,
      // ya'ni shuncha xato ahamiyatsiz — uni yo'qotish uchun
      // `atan2(|a×b|, a·b)` shakliga o'tish kerak bo'lardi va bu
      // hech narsa bermaydi.
      expect(angularSeparationDeg(30, 10, 30, 10), closeTo(0, 1e-4));
    });

    test('gorizontda oddiy ayirma', () {
      expect(angularSeparationDeg(0, 0, 40, 0), closeTo(40, 1e-6));
    });

    test('CHOKDAN o‘tgan ayirma to‘g‘ri hisoblanadi', () {
      // `350` va `10` orasida 20°, 340° emas. Oddiy ayirma bilan
      // hisoblansa ikki yonma-yon tugma «uzoq» deb o'tib ketardi.
      expect(angularSeparationDeg(350, 0, 10, 0), closeTo(20, 1e-6));
    });

    test('QUTBGA yaqin joyda yaw ayirmasi ALDAYDI', () {
      // Bu funksiyaning butun sababi. `pitch = 85` da yaw'i 90° farq
      // qiladigan ikki nuqta amalda ~9° uzoqlikda — ya'ni tugmalar
      // ustma-ust tushadi, lekin oddiy yaw ayirmasi ularni «uzoq»
      // deb o'tkazib yuborardi.
      final double sep = angularSeparationDeg(0, 85, 90, 85);
      expect(sep, lessThan(15));
      expect(sep, greaterThan(0));
    });

    test('qarama-qarshi tomon — 180', () {
      expect(angularSeparationDeg(0, 0, 180, 0), closeTo(180, 1e-6));
    });
  });

  group('overlappingLink', () {
    test('yaqin tugma TOPILADI', () {
      final links = <TourLink>[link(p1, p2, yaw: 100)];
      expect(overlappingLink(links, p1, 105, 0), isNotNull);
    });

    test('uzoq tugma topilmaydi', () {
      final links = <TourLink>[link(p1, p2, yaw: 100)];
      expect(overlappingLink(links, p1, 160, 0), isNull);
    });

    test('BOSHQA panoramadagi tugma hisobga olinmaydi', () {
      // Har panorama o'z sferasi — ikkinchisidagi tugma bu yerda
      // ko'rinmaydi ham.
      final links = <TourLink>[link(p2, p3, yaw: 100)];
      expect(overlappingLink(links, p1, 100, 0), isNull);
    });
  });

  group('linksFrom / hasLink', () {
    final links = <TourLink>[link(p1, p2), link(p1, p3), link(p2, p1)];

    test('faqat shu panoramadan chiqadiganlar', () {
      expect(linksFrom(links, p1), hasLength(2));
      expect(linksFrom(links, p2), hasLength(1));
      expect(linksFrom(links, p3), isEmpty);
    });

    test('hasLink yo‘nalishni HISOBGA OLADI', () {
      expect(hasLink(links, p1, p2), isTrue);
      expect(hasLink(links, p3, p1), isFalse);
    });
  });

  group('JSON aylanma yo‘li', () {
    test('yozib-o‘qilganda o‘zgarmaydi', () {
      const t = TourLink(
        from: p1,
        to: p2,
        yawDeg: 123.5,
        pitchDeg: -12.25,
        label: 'Oshxona',
      );
      expect(TourLink.fromJson(t.toJson()), t);
    });

    test('SERVER shakli ham o‘qiladi (`from_key`/`to_key`)', () {
      // Tahrirlashda havolalar serverdan shu nomlar bilan keladi.
      final t = TourLink.fromJson(<String, Object?>{
        'from_key': k1,
        'to_key': k2,
        'yaw_deg': 45,
        'pitch_deg': 0,
      });
      expect(t.from, k1);
      expect(t.to, k2);
      expect(t.yawDeg, 45);
    });

    test('bo‘sh yorliq NULL bo‘ladi', () {
      final t = TourLink.fromJson(<String, Object?>{
        'from': p1,
        'to': p2,
        'label': '   ',
      });
      expect(t.label, isNull);
    });
  });

  test('mobil chegara BACKEND bilan bir xil', () {
    // Farq qilsa foydalanuvchi tugma qo'sha olardi, server esa butun
    // e'lonni 400 bilan rad etardi — sababi tushunarsiz bo'lardi.
    expect(kMaxTourLinksPerPanorama, 8);
  });
}
