import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/stitch/raster.dart';

/// Raster yadrolari — OpenCV o'rnini bosadigan amallar.
///
/// Bu testlarning ko'pi «to'g'ri hisoblaydimi» degan savolga emas,
/// rejadagi JIM VA HALOKATLI farqlar jadvaliga javob beradi
/// (`docs/panorama-360-plan.md`, 4.2-bo'lim). Har biri kompilyatsiya xatosi
/// bermaydigan, faqat natijani buzadigan farqni qotiradi.
void main() {
  Float32List f(List<num> v) =>
      Float32List.fromList(v.map((e) => e.toDouble()).toList());

  /// Gradient plan — chegara xatolari shunda ko'rinadi.
  Float32List ramp(int w, int h) {
    final out = Float32List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        out[y * w + x] = (x + y * w).toDouble();
      }
    }
    return out;
  }

  group('reflect101 — BORDER_REFLECT_101', () {
    test('chegara pikselini TAKRORLAMAYDI', () {
      // gfedcb|abcdefgh|gfedcba — ya'ni -1 → 1, emas 0.
      expect(reflect101(-1, 8), 1);
      expect(reflect101(-2, 8), 2);
      expect(reflect101(8, 8), 6);
      expect(reflect101(9, 8), 5);
    });

    test('ichkarida o‘zgartirmaydi', () {
      for (int i = 0; i < 8; i++) {
        expect(reflect101(i, 8), i);
      }
    });

    test('BORDER_REFLECT dan FARQ qiladi', () {
      // Takrorlaydigan variant -1 → 0 berardi. Aralashtirish chegarada
      // yarim piksel siljish beradi — panorama chetida ko'rinadigan chiziq.
      expect(reflect101(-1, 8), isNot(0));
    });

    test('bir pikselli o‘lchamda ham ishlaydi', () {
      // Piramidaning eng qo'pol oktavasi 1 pikselgacha tushishi mumkin.
      expect(reflect101(-3, 1), 0);
      expect(reflect101(5, 1), 0);
    });

    test('juda uzoq indeks ham davriy', () {
      expect(reflect101(-100, 8), reflect101(-100 + 14 * 7, 8));
      expect(reflect101(100, 8), inInclusiveRange(0, 7));
    });
  });

  group('saturateCastU8 — saturate + ROUND', () {
    test('yaxlitlaydi, kesmaydi', () {
      // `.toInt()` bo'lsa 127 chiqardi va butun panorama qorayardi.
      expect(saturateCastU8(127.5), 128);
      expect(saturateCastU8(127.4), 127);
      expect(saturateCastU8(0.6), 1);
    });

    test('0..255 ga qisadi', () {
      expect(saturateCastU8(-10), 0);
      expect(saturateCastU8(300), 255);
      expect(saturateCastU8(255.4), 255);
    });

    test('NaN qora beradi, tashlanmaydi', () {
      // NaN quvurga sizib kirsa `.round()` istisno tashlaydi va butun
      // tikish yiqiladi — qora piksel esa ko'rinadigan nosozlik.
      expect(saturateCastU8(double.nan), 0);
    });

    test('toU8 alpha/beta bilan convertTo kabi ishlaydi', () {
      expect(toU8(f([1, 2]), alpha: 100), Uint8List.fromList([100, 200]));
      expect(toU8(f([1]), alpha: 100, beta: 60), Uint8List.fromList([160]));
      expect(toU8(f([10]), alpha: 100), Uint8List.fromList([255]));
    });
  });

  group('divideSafe — 0/0 NaN emas', () {
    test('nolga bo‘lish NaN bermaydi', () {
      // OpenCV 0/0 uchun 0 qaytaradi, Dart esa NaN — va NaN keyingi hamma
      // amalga yuqadi: tuvalning bitta qoplanmagan pikseli butun bandni
      // NaN qilib qo'yadi.
      final r = divideSafe(f([0, 5]), f([0, 0]));
      expect(r[0].isNaN, isFalse);
      expect(r[0], closeTo(0, 1e-9));
      expect(r[1].isFinite, isTrue);
    });

    test('oddiy bo‘linishni sezilarli buzmaydi', () {
      final r = divideSafe(f([10]), f([4]));
      expect(r[0], closeTo(2.5, 1e-4));
    });
  });

  group('compareGt — QAT‘IY >', () {
    test('teng qiymatda 0 qaytaradi', () {
      // `>=` bo'lsa teng og'irlikda oxirgi kadr yutadi va butun label
      // xaritasi, chok yo'nalishi va blend boshqacha bo'ladi.
      expect(compareGt(f([5]), f([5])), Uint8List.fromList([0]));
      expect(compareGt(f([5.0001]), f([5])), Uint8List.fromList([255]));
      expect(compareGt(f([4.9999]), f([5])), Uint8List.fromList([0]));
    });

    test('255/0 beradi, 1/0 emas', () {
      expect(compareGt(f([1]), f([0]))[0], 255);
    });
  });

  group('nearestIndexMap — floor, yaxlitlash EMAS', () {
    test('indeks floor(dst·src/dstSize)', () {
      // 10 → 3: dst 0,1,2 → floor(0), floor(3.33), floor(6.67) = 0,3,6.
      // Yaxlitlansa 0,3,7 bo'lardi va label chegarasi siljirdi.
      final m = nearestIndexMap(10, 1, 3, 1);
      expect(m, Int32List.fromList([0, 3, 6]));
    });

    test('oxirgi indeks chegaradan chiqmaydi', () {
      final m = nearestIndexMap(4, 4, 4, 4);
      expect(m.reduce(math.max), 15);
      final m2 = nearestIndexMap(3, 1, 7, 1);
      expect(m2.reduce(math.max), lessThanOrEqualTo(2));
    });

    test('label masshtablash mavjud bo‘lmagan qiymat YARATMAYDI', () {
      // Float orqali masshtablansa 7 va 9 orasida 8 paydo bo'lishi mumkin.
      final src = Int32List.fromList([7, 7, 9, 9]);
      final out = resizeNearestLabels(src, 4, 1, 2, 1);
      expect(out.toSet(), <int>{7, 9});
      expect(out.toSet().difference(src.toSet()), isEmpty);
    });
  });

  group('resizeArea — qismiy chegara og‘irligi', () {
    test('butun koeffitsiyentda oddiy o‘rtacha', () {
      final out = resizeArea(f([1, 2, 3, 4]), 4, 1, 2, 1);
      expect(out[0], closeTo(1.5, 1e-5));
      expect(out[1], closeTo(3.5, 1e-5));
    });

    test('KASR koeffitsiyentda chegara pikseli QISMIY og‘irlik oladi', () {
      // 3 → 2, ya'ni s = 1.5. Birinchi dst [0, 1.5) ni qamraydi:
      // src[0] to'liq (og'irlik 1/1.5), src[1] yarim (0.5/1.5).
      // Oddiy box o'rtacha (src[0], src[1] teng) 1.5 berardi — noto'g'ri.
      final out = resizeArea(f([1, 2, 3]), 3, 1, 2, 1);
      expect(out[0], closeTo((1 * 1 + 2 * 0.5) / 1.5, 1e-5));
      expect(out[0], closeTo(1.3333, 1e-4));
      expect(out[0], isNot(closeTo(1.5, 1e-3)), reason: 'box o‘rtacha emas');
      expect(out[1], closeTo((2 * 0.5 + 3 * 1) / 1.5, 1e-5));
    });

    test('tekis planni o‘zgartirmaydi (og‘irliklar 1 ga yig‘iladi)', () {
      final flat = Float32List(7 * 5)..fillRange(0, 35, 42);
      final out = resizeArea(flat, 7, 5, 3, 2);
      for (final v in out) {
        expect(v, closeTo(42, 1e-4));
      }
    });

    test('o‘rtacha qiymat saqlanadi', () {
      final src = ramp(8, 6);
      final out = resizeArea(src, 8, 6, 4, 3);
      final double srcMean = src.reduce((a, b) => a + b) / src.length;
      final double outMean = out.reduce((a, b) => a + b) / out.length;
      expect(outMean, closeTo(srcMean, 1e-2));
    });

    test('KATTALASHTIRISH ochiq rad etiladi', () {
      // OpenCV bu holatda INTER_NEAREST ga o'xshash ishlaydi. Jimgina
      // boshqa natija berishdan ko'ra assert bilan to'xtatiladi.
      expect(
        () => resizeArea(f([1, 2]), 2, 1, 4, 1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('resizeLinear — yarim piksel markazi', () {
    test('teng o‘lchamda o‘zgartirmaydi', () {
      final src = ramp(5, 4);
      final out = resizeLinear(src, 5, 4, 5, 4);
      for (int i = 0; i < src.length; i++) {
        expect(out[i], closeTo(src[i], 1e-4));
      }
    });

    test('2× kattalashtirishda markaz kelishuvi ishlatiladi', () {
      // `fx = (dx+0.5)·0.5 - 0.5`: dst 0 → -0.25 (qisiladi → src[0]),
      // dst 1 → 0.25, dst 2 → 0.75. `dx·s` bo'lsa 0, 0.5, 1.0 bo'lardi —
      // butun tasvir yarim piksel siljirdi.
      final out = resizeLinear(f([0, 4]), 2, 1, 4, 1);
      expect(out[0], closeTo(0, 1e-4), reason: 'chapga qisiladi');
      expect(out[1], closeTo(1, 1e-4));
      expect(out[2], closeTo(3, 1e-4));
      expect(out[3], closeTo(4, 1e-4), reason: 'o‘ngga qisiladi');
    });

    test('tekis planni o‘zgartirmaydi', () {
      final flat = Float32List(4 * 4)..fillRange(0, 16, 7);
      for (final v in resizeLinear(flat, 4, 4, 9, 3)) {
        expect(v, closeTo(7, 1e-4));
      }
    });
  });

  group('remapBilinear', () {
    test('birlik xarita tasvirni o‘zgartirmaydi', () {
      const w = 4, h = 3;
      final src = ramp(w, h);
      final mx = Float32List(w * h);
      final my = Float32List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          mx[y * w + x] = x.toDouble();
          my[y * w + x] = y.toDouble();
        }
      }
      final out = remapBilinear(src, w, h, mx, my, w, h);
      for (int i = 0; i < src.length; i++) {
        expect(out[i], closeTo(src[i], 1e-4));
      }
    });

    test('yarim piksel siljish o‘rtacha beradi', () {
      final out = remapBilinear(
        f([0, 10]),
        2,
        1,
        f([0.5]),
        f([0]),
        1,
        1,
      );
      expect(out[0], closeTo(5, 1e-4));
    });

    test('manba TASHQARISI qora (BORDER_CONSTANT) — sukut', () {
      // `cv.remap` sukut chegarasi shunday va quvur shunga tayanadi:
      // qoplanmagan joy 0 bo'ladi va maska aynan shuni o'qiydi. Chegara
      // REPLICATE bo'lsa tuvalda kadr cho'zilib ketardi va maska
      // qoplanmagan joyni qoplangan deb ko'rsatardi.
      final out = remapBilinear(f([5, 5]), 2, 1, f([-50, 50]), f([0, 0]), 2, 1);
      expect(out[0], 0);
      expect(out[1], 0);
    });

    test('replicate berilsa chegara cho‘ziladi', () {
      final out = remapBilinear(
        f([5, 9]),
        2,
        1,
        f([-50, 50]),
        f([0, 0]),
        2,
        1,
        replicate: true,
      );
      expect(out[0], closeTo(5, 1e-4));
      expect(out[1], closeTo(9, 1e-4));
    });

    test('DST o‘lchami manbadan farq qilishi mumkin', () {
      final out = remapBilinear(ramp(4, 4), 4, 4, f([0, 1]), f([0, 0]), 2, 1);
      expect(out, hasLength(2));
    });
  });

  group('pyrDown — [1,4,6,4,1]/16', () {
    test('yadro 1 ga yig‘iladi', () {
      expect(kPyrKernel.reduce((a, b) => a + b), closeTo(1, 1e-12));
      expect(kPyrKernel, <double>[1 / 16, 4 / 16, 6 / 16, 4 / 16, 1 / 16]);
    });

    test('tekis planni CHETIDA ham o‘zgartirmaydi', () {
      // Chegara aks ettirish xato bo'lsa aynan chetlarda qorong'i
      // halqa paydo bo'ladi — bu esa feather kengligini buzadi.
      final flat = Float32List(9 * 7)..fillRange(0, 63, 100);
      final out = pyrDown(flat, 9, 7);
      for (final v in out) {
        expect(v, closeTo(100, 1e-3));
      }
    });

    test('sukut o‘lchami (n+1)~/2', () {
      expect(pyrDown(Float32List(9 * 7), 9, 7), hasLength(5 * 4));
      expect(pyrDown(Float32List(8 * 8), 8, 8), hasLength(4 * 4));
    });

    test('aniq o‘lcham berilishi mumkin, lekin 1 dan ko‘p farq qilmaydi', () {
      expect(pyrDown(Float32List(9 * 7), 9, 7, dw: 4, dh: 4), hasLength(16));
      expect(
        () => pyrDown(Float32List(9 * 7), 9, 7, dw: 2, dh: 4),
        throwsA(isA<AssertionError>()),
      );
    });

    test('silliqlaydi — nuqta impuls tarqaladi', () {
      final src = Float32List(9 * 9);
      src[4 * 9 + 4] = 1600;
      final out = pyrDown(src, 9, 9);
      // 5×5 chiqishda impuls markaziga 6/16·6/16 = 0.1406 tushadi.
      expect(out[2 * 5 + 2], closeTo(1600 * 36 / 256, 1e-2));
      // Energiya taxminan chorak qismga tushadi (decimatsiya).
      expect(out.reduce((a, b) => a + b), closeTo(400, 1));
    });
  });

  group('pyrUp', () {
    test('tekis planni o‘zgartirmaydi (×4 to‘g‘ri)', () {
      // ×4 koeffitsiyenti xato bo'lsa butun oktava yorishadi yoki
      // qorayadi va Laplas ayirmasi butunlay boshqa bo'ladi.
      final flat = Float32List(5 * 4)..fillRange(0, 20, 30);
      final out = pyrUp(flat, 5, 4);
      expect(out, hasLength(10 * 8));
      for (final v in out) {
        expect(v, closeTo(30, 1e-3));
      }
    });

    test('sukut o‘lchami 2×, aniq o‘lcham ham beriladi', () {
      expect(pyrUp(Float32List(4), 2, 2), hasLength(16));
      expect(pyrUp(Float32List(4), 2, 2, dw: 3, dh: 3), hasLength(9));
    });

    test('Laplas qayta tiklash — pyrUp(pyrDown) tekisda AYNAN qaytadi', () {
      // Piramida quvurining asosiy invarianti: `src - pyrUp(pyrDown(src))`
      // (Laplas) ni qaytib qo'shganda asl qiymat chiqishi kerak. Tekis
      // planda bu AYNAN bajarilishi shart, aks holda oktavalar bo'ylab
      // xato yig'ilib panorama pog'onali bo'lib chiqadi.
      const w = 8, h = 8;
      final src = Float32List(w * h)..fillRange(0, w * h, 55);
      final down = pyrDown(src, w, h);
      final up = pyrUp(down, 4, 4, dw: w, dh: h);
      final lap = subtract(src, up);
      final back = add(up, lap);
      for (int i = 0; i < src.length; i++) {
        expect(lap[i], closeTo(0, 1e-3), reason: 'tekisda Laplas nol');
        expect(back[i], closeTo(src[i], 1e-3));
      }
    });

    test('Laplas qayta tiklash GRADIENTDA ham aynan qaytadi', () {
      // Bu `add`/`subtract` juftligining invarianti — pyrUp aniqligiga
      // bog'liq emas, lekin quvur aynan shunga tayanadi.
      const w = 8, h = 6;
      final src = ramp(w, h);
      final up = pyrUp(pyrDown(src, w, h), 4, 3, dw: w, dh: h);
      final back = add(up, subtract(src, up));
      for (int i = 0; i < src.length; i++) {
        expect(back[i], closeTo(src[i], 1e-2));
      }
    });
  });

  group('element-wise', () {
    test('to‘rt amal', () {
      expect(add(f([1, 2]), f([3, 4])), f([4, 6]));
      expect(subtract(f([5, 5]), f([1, 2])), f([4, 3]));
      expect(multiply(f([2, 3]), f([4, 5])), f([8, 15]));
      expect(absDiff(f([1, 9]), f([4, 4])), f([3, 5]));
      expect(maxOf(f([1, 9]), f([4, 4])), f([4, 9]));
    });

    test('o‘lcham mos kelmasa assert', () {
      expect(() => add(f([1]), f([1, 2])), throwsA(isA<AssertionError>()));
    });

    test('threshold QAT‘IY > bilan ishlaydi', () {
      expect(threshold(f([0.5, 0.5001]), 0.5), Uint8List.fromList([0, 255]));
    });

    test('countNonZero', () {
      expect(countNonZero(Uint8List.fromList([0, 1, 0, 255])), 2);
      expect(countNonZero(Uint8List(0)), 0);
    });

    test('toF32/toU8 aylanishi qiymatni saqlaydi', () {
      final u = Uint8List.fromList([0, 1, 128, 255]);
      expect(toU8(toF32(u)), u);
    });
  });
}
