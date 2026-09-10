import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/stitch/raw_plane.dart';

/// Xom kadr keshi formati.
///
/// Testlarning YARMI «to'g'ri o'qiydimi» degan savolga emas, **«buzuq
/// faylni RAD ETADIMI»** degan savolga javob beradi. Sabab: disk to'lib
/// qolsa yoki ilova yozish o'rtasida o'ldirilsa keshda qisqa fayl
/// qoladi. Uni «bor narsasi bilan» o'qish kadrni siljigan holda beradi va
/// panorama sababsiz buziladi — hech qanday xato chiqmasdan.
void main() {
  Uint8List fill(int w, int h, List<int> perChannel) {
    final out = Uint8List(w * h * perChannel.length);
    for (int c = 0; c < perChannel.length; c++) {
      out.fillRange(c * w * h, (c + 1) * w * h, perChannel[c]);
    }
    return out;
  }

  RawPlane sample({int w = 4, int h = 3, List<int> ch = const [10, 20, 30]}) =>
      RawPlane(
        width: w,
        height: h,
        channels: ch.length,
        bytes: fill(w, h, ch),
      );

  group('planar joylashuv', () {
    test('kanallar KETMA-KET saqlanadi, interleaved emas', () {
      // Interleaved bo'lsa `plane(0)` aralash qiymat qaytarardi va butun
      // raster qatlami (bir kanalli planar) noto'g'ri ishlardi.
      final p = sample();
      expect(p.plane(0).every((v) => v == 10), isTrue);
      expect(p.plane(1).every((v) => v == 20), isTrue);
      expect(p.plane(2).every((v) => v == 30), isTrue);
      expect(p.plane(0), hasLength(12));
    });

    test('plane() NUSXA emas, ko‘rinish', () {
      // 76 kadr uchun nusxa olish yuzlab megabayt ortiqcha ish bo'lardi.
      final p = sample();
      p.plane(1)[0] = 99;
      expect(p.bytes[p.pixelsPerChannel], 99);
    });

    test('mavjud bo‘lmagan kanal assert', () {
      expect(() => sample().plane(3), throwsA(isA<AssertionError>()));
      expect(() => sample().plane(-1), throwsA(isA<AssertionError>()));
    });

    test('bufer uzunligi o‘lchamga mos kelmasa assert', () {
      expect(
        () => RawPlane(
          width: 4,
          height: 3,
          channels: 3,
          bytes: Uint8List(10),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('bir kanalli ham ishlaydi (kulrang kadr)', () {
      final p = RawPlane(
        width: 2,
        height: 2,
        channels: 1,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );
      expect(p.plane(0), Uint8List.fromList([1, 2, 3, 4]));
    });
  });

  group('encode / decode aylanishi', () {
    test('baytma-bayt aynan qaytadi', () {
      final p = sample(w: 7, h: 5);
      final back = RawPlane.decode(p.encode());
      expect(back.width, 7);
      expect(back.height, 5);
      expect(back.channels, 3);
      expect(back.bytes, p.bytes);
    });

    test('sarlavha 16 bayt va PRW1 bilan boshlanadi', () {
      final e = sample().encode();
      expect(e.length, kRawPlaneHeaderBytes + 4 * 3 * 3);
      // 'PRW1' little-endian yozilgan: 31 57 52 50.
      expect(e.sublist(0, 4), Uint8List.fromList([0x31, 0x57, 0x52, 0x50]));
    });

    test('endianlik OCHIQ — sukutga tashlanmagan', () {
      // Sukutga tashlansa kesh fayli boshqa arxitekturada boshqacha
      // o'qilardi (qurilma ARM64, simulyator x86_64 bo'lishi mumkin).
      final e = sample(w: 258, h: 1, ch: const [7]).encode();
      final head = ByteData.sublistView(e, 0, kRawPlaneHeaderBytes);
      expect(head.getUint32(4, Endian.little), 258);
      expect(e[4], 2, reason: 'past bayt oldinda — little-endian');
      expect(e[5], 1);
    });

    test('katta kadr ham aynan qaytadi', () {
      final p = RawPlane(
        width: 701,
        height: 1246,
        channels: 3,
        bytes: Uint8List(701 * 1246 * 3)
          ..asMap().forEach((i, _) {}),
      );
      for (int i = 0; i < p.bytes.length; i += 7919) {
        p.bytes[i] = i % 251;
      }
      final back = RawPlane.decode(p.encode());
      expect(back.bytes, p.bytes);
      expect(back.width * back.height * back.channels, p.bytes.length);
    });

    test('decode NUSXA olmaydi — ko‘rinish qaytaradi', () {
      final raw = sample().encode();
      final back = RawPlane.decode(raw);
      back.bytes[0] = 77;
      expect(raw[kRawPlaneHeaderBytes], 77);
    });
  });

  group('BUZUQ faylni rad etish', () {
    test('YARIM YOZILGAN fayl rad etiladi', () {
      // Eng muhim test: disk to'lganda yoki ilova o'ldirilganda aynan
      // shunday fayl qoladi.
      final full = sample(w: 8, h: 8).encode();
      final half = Uint8List.sublistView(full, 0, full.length - 10);
      expect(
        () => RawPlane.decode(half),
        throwsA(
          isA<RawPlaneFormatException>().having(
            (e) => e.message,
            'message',
            contains('yarim yozilgan'),
          ),
        ),
      );
    });

    test('ORTIQCHA uzun fayl ham rad etiladi', () {
      // Bu ham buzilish alomati — masalan ikki yozuv ustma-ust tushgan.
      final e = sample().encode();
      final longer = Uint8List(e.length + 5)..setRange(0, e.length, e);
      expect(() => RawPlane.decode(longer), throwsA(isA<RawPlaneFormatException>()));
    });

    test('boshqa magic rad etiladi (eski versiya yoki begona fayl)', () {
      final e = sample().encode();
      e[0] = 0x30; // 'PRW0'
      expect(
        () => RawPlane.decode(e),
        throwsA(
          isA<RawPlaneFormatException>().having(
            (x) => x.message,
            'message',
            contains('PRW1 emas'),
          ),
        ),
      );
    });

    test('sarlavhadan qisqa fayl rad etiladi', () {
      expect(() => RawPlane.decode(Uint8List(4)), throwsA(isA<RawPlaneFormatException>()));
      expect(() => RawPlane.decode(Uint8List(0)), throwsA(isA<RawPlaneFormatException>()));
    });

    test('MA’NOSIZ o‘lchamlar rad etiladi', () {
      // Nol yoki ulkan o'lcham xotira ajratishga urinishdan OLDIN
      // to'xtatilishi kerak.
      final e = sample().encode();
      final head = ByteData.sublistView(e, 0, kRawPlaneHeaderBytes);
      head.setUint32(4, 0, Endian.little); // width = 0
      expect(() => RawPlane.decode(e), throwsA(isA<RawPlaneFormatException>()));

      head.setUint32(4, 4, Endian.little);
      head.setUint8(12, 9); // channels = 9
      expect(() => RawPlane.decode(e), throwsA(isA<RawPlaneFormatException>()));
    });

    test('channels = 0 rad etiladi — uzunlik tekshiruvi buni O‘TKAZADI', () {
      // Bu o'lchov tekshiruvining YAGONA haqiqiy roli: `1×1×0` uchun
      // `need = 0` va bo'sh payload bilan `have = 0`, ya'ni uzunlik
      // tekshiruvi RAZI bo'ladi. O'lchov tekshiruvisiz `RawPlane`
      // yasalardi va `plane(0)` quvurning ichida `RangeError` tashlardi
      // — release'da assert'lar o'chirilgan, ya'ni himoya faqat shu
      // tekshiruvda.
      final b = Uint8List(kRawPlaneHeaderBytes);
      final d = ByteData.sublistView(b);
      d.setUint32(0, kRawPlaneMagic, Endian.little);
      d.setUint32(4, 1, Endian.little);
      d.setUint32(8, 1, Endian.little);
      d.setUint8(12, 0);
      expect(
        () => RawPlane.decode(b),
        throwsA(
          isA<RawPlaneFormatException>().having(
            (e) => e.message,
            'message',
            contains('ma\'nosiz'),
          ),
        ),
      );
    });

    test('ulkan o‘lcham xotira ajratmasdan rad etiladi', () {
      final e = sample().encode();
      final head = ByteData.sublistView(e, 0, kRawPlaneHeaderBytes);
      head.setUint32(4, 0xFFFF, Endian.little);
      head.setUint32(8, 0xFFFF, Endian.little);
      // Uzunlik tekshiruvi ajratishdan oldin ishlaydi — istisno, OOM emas.
      expect(() => RawPlane.decode(e), throwsA(isA<RawPlaneFormatException>()));
    });

    test('xato matni NIMA bo‘lganini aytadi', () {
      // Diagnostikasiz «format xatosi» qurilmada foydasiz.
      try {
        RawPlane.decode(Uint8List.sublistView(sample().encode(), 0, 20));
        fail('istisno kutilgandi');
      } on RawPlaneFormatException catch (e) {
        expect(e.toString(), contains('bayt'));
        expect(e.toString(), contains('kerak'));
      }
    });
  });
}
