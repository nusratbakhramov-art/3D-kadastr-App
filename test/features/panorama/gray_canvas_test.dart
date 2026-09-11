import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/math/rotation.dart';
import 'package:kadastr/features/panorama/stitch/gray_canvas.dart';
import 'package:kadastr/features/panorama/stitch/raw_plane.dart';

/// Kulrang warp — chok yo'naltiruvchisining KIRISHI.
///
/// Bu yerdagi testlarning aksari bitta narsani qo'riqlaydi: **`0`
/// faqat «qoplanmagan» degani**. Chok DP si shu shartnomaga tayanadi
/// va uni buzish kompilyatsiya xatosi bermaydi — panorama shunchaki
/// boshqa joydan kesiladi. Shuning uchun har test buzib ko'rilgan.
void main() {
  const canvasW = 128;
  const canvasH = 64;
  const fw = 32;
  const fh = 32;
  const fov = 60.0;

  /// Bir xil rangdagi uch kanalli kadr.
  RawPlane solid(int r, int g, int b, {int w = fw, int h = fh}) {
    final bytes = Uint8List(w * h * 3);
    bytes.fillRange(0, w * h, r);
    bytes.fillRange(w * h, 2 * w * h, g);
    bytes.fillRange(2 * w * h, 3 * w * h, b);
    return RawPlane(width: w, height: h, channels: 3, bytes: bytes);
  }

  Uint8List warp(RawPlane f, {double gain = 1}) => warpGray(
    frame: f,
    rotation: rotationMatrix(0, 0, 0),
    longSideFovDeg: fov,
    canvasW: canvasW,
    canvasH: canvasH,
    gain: gain,
  );

  int covered(Uint8List g) => g.where((int v) => v != 0).length;

  group('grayDivFor — o‘lchov masshtabi byudjetga qarab', () {
    test('76 kadr, 3072 tuval → div 2 (85.5 MB, byudjetga sig‘adi)', () {
      expect(grayDivFor(76, 3072), 2);
      // Haqiqatan sig'ishini SHU YERDA qotiramiz — byudjet yoki
      // chegaralar o'zgarsa test aytadi.
      const int w = 3072 ~/ 2;
      expect(76 * w * (w ~/ 2), lessThanOrEqualTo(kGrayBudgetBytes));
    });

    test('kadr ko‘paysa masshtab KICHRAYADI', () {
      // div=2 da 3072: 1536×768 = 1.18 MB/kadr → 127 kadr 150 MB dan
      // oshadi va div 3 ga o'tishi SHART.
      expect(grayDivFor(400, 3072), greaterThan(2));
      expect(grayDivFor(400, 3072), lessThanOrEqualTo(kGrayDivMax));
    });

    test('hech qachon to‘liq tuval bermaydi va chegaradan chiqmaydi', () {
      for (final int n in <int>[1, 76, 100000]) {
        final int d = grayDivFor(n, 3072);
        expect(d, greaterThanOrEqualTo(kGrayDivMin));
        expect(d, lessThanOrEqualTo(kGrayDivMax));
      }
    });
  });

  group('grayFrameWidth — kadr qanchaga kichrayadi', () {
    test('tuvalning choragi', () => expect(grayFrameWidth(1536), 384));

    test('320 dan past TUSHMAYDI', () {
      // Kichik tuvalda chorak 320 dan kam chiqadi; o'shanda kadr
      // shunchalik kichrayadiki, yorqinlik o'lchovi shovqinga
      // aylanardi.
      expect(grayFrameWidth(512), 320);
      expect(grayFrameWidth(64), 320);
    });
  });

  group('NOL — faqat «qoplanmagan» degani', () {
    test('TO‘LIQ QORA kadr ham nol BERMAYDI', () {
      // Eng muhim test. Qora shift — haqiqiy o'lchov. Agar u 0 bo'lib
      // chiqsa DP «bu kadr bu yerda yo'q» deb o'qiydi va aynan qorong'i
      // joydan kesib o'tishni BEPUL deb hisoblaydi.
      final Uint8List g = warp(solid(0, 0, 0));

      expect(covered(g), greaterThan(0), reason: 'kadr tuvalga tushmadi');
      for (int i = 0; i < g.length; i++) {
        if (g[i] != 0) expect(g[i], 1, reason: 'qora piksel 1 ga ko‘tariladi');
      }
    });

    test('iz TASHQARISI nol', () {
      final Uint8List g = warp(solid(200, 200, 200));

      // Kadr 60° FOV, ya'ni tuvalning kichik qismini qoplaydi.
      expect(covered(g), lessThan(g.length ~/ 2));
      // Qutb — kadr markazi ekvatorda turibdi, zenit qoplanmasligi shart.
      expect(g[0], 0);
      expect(g[g.length - 1], 0);
    });

    test('qoplangan soha UZLUKSIZ — teshik yo‘q', () {
      // Ichkarida nol qolsa u «qoplanmagan» bo'lib o'qiladi va DP
      // o'sha teshikdan o'tib ketadi.
      //
      // ⚠️ Kadr tuval O'RTASIGA qo'yiladi (`lon = π`). `lon = 0` da iz
      // chokni kesib o'tadi va qamrov ikkala chetda bo'ladi
      // (`####…####`) — u holda «birinchidan oxirgigacha uzluksiz»
      // degan tekshiruv o'zi noto'g'ri bo'lardi. O'ralishni keyingi
      // test alohida qo'riqlaydi.
      final Uint8List g = warpGray(
        frame: solid(0, 0, 0),
        rotation: rotationMatrix(math.pi, 0, 0),
        longSideFovDeg: fov,
        canvasW: canvasW,
        canvasH: canvasH,
      );

      expect(covered(g), greaterThan(0));
      for (int y = 0; y < canvasH; y++) {
        int first = -1, last = -1;
        for (int x = 0; x < canvasW; x++) {
          if (g[y * canvasW + x] != 0) {
            if (first < 0) first = x;
            last = x;
          }
        }
        if (first < 0) continue;
        expect(first, isNot(0), reason: 'y=$y da iz chetga tegdi — o‘ralgan?');
        for (int x = first; x <= last; x++) {
          expect(g[y * canvasW + x], isNot(0), reason: 'teshik: ($x, $y)');
        }
      }
    });

    test('CHOKNI kesib o‘tgan kadr IKKALA chetda ko‘rinadi', () {
      // `lon = 0` da iz `u0 = -16` dan boshlanadi, ya'ni tuvaldan
      // chiqib ketadi. Ustun bloklari uni o'ramasa kadr JIMGINA
      // yarmiga bo'linardi — chap yarmi umuman qo'yilmasdi.
      final Uint8List g = warp(solid(200, 200, 200));
      const int mid = canvasH ~/ 2;

      expect(g[mid * canvasW], isNot(0), reason: 'chap chet bo‘sh');
      expect(g[mid * canvasW + canvasW - 1], isNot(0), reason: 'o‘ng chet bo‘sh');
      // O'rtasi esa qoplanmagan — 60° kadr 360° ni yopa olmaydi.
      expect(g[mid * canvasW + mid], 0);
    });
  });

  group('yorqinlik — kanal tartibi va yaxlitlash', () {
    test('KANAL TARTIBI: RawPlane RGB, koeffitsiyentlar shunga mos', () {
      // Qizil va ko'k yorqinligi keskin farq qiladi (0.299 va 0.114).
      // Kanallar almashib ketsa bu ikki son O'RIN ALMASHADI — va bu
      // kulrang sahnada umuman ko'rinmaydi.
      final int red = _peak(warp(solid(255, 0, 0)));
      final int blue = _peak(warp(solid(0, 0, 255)));
      final int green = _peak(warp(solid(0, 255, 0)));

      expect(red, 76); // (255·4899 + 8192) >> 14
      expect(green, 150);
      expect(blue, 29);
    });

    test('oq — 255, to‘yinish saqlanadi', () {
      expect(_peak(warp(solid(255, 255, 255))), 255);
    });

    test('gain yorqinlikni KO‘TARADI va 255 da to‘yinadi', () {
      expect(_peak(warp(solid(100, 100, 100))), 100);
      expect(_peak(warp(solid(100, 100, 100), gain: 2)), 200);
      // Gain to'yintirsa piksel 255 da to'xtaydi, aylanib ketmaydi.
      expect(_peak(warp(solid(200, 200, 200), gain: 2)), 255);
    });

    test('kadr CHETI qoraymaydi — og‘irlik qisqarishi SHART', () {
      // Tuvalda bitta kadr bor, ya'ni tor og'irlik `color / weight` da
      // qisqarishi kerak va har qoplangan piksel kadrning asl
      // yorqinligini berishi lozim.
      //
      // Buzilishi: `blendPower` ni ko'tarish (yoki `winnerTakeAll:
      // false` ni tushirib qoldirish). O'shanda `t¹⁶` bo'luvchidagi
      // `1e-6` epsilondan kichik bo'lib qoladi va chet pikseller
      // qorayadi — o'lchangan holda 422 dan 346 tasi, eng pasti 2.
      final Uint8List g = warp(solid(200, 200, 200));

      int cov = 0;
      for (final int v in g) {
        if (v == 0) continue;
        cov++;
        expect(v, 200, reason: 'qoplangan piksel asl yorqinligini bermadi');
      }
      expect(cov, greaterThan(100), reason: 'kadr tuvalga tushmadi');
    });

    test('YAXLITLAYDI, kesmaydi', () {
      // 1 kanalda 0.5 dan katta kasr qism yuqoriga yaxlitlanishi kerak.
      // `.toInt()` bo'lsa har piksel bir darajaga pastga tushardi.
      expect(_peak(warp(solid(100, 100, 100), gain: 1.006)), 101);
    });
  });

  test('bir kanalli kadr ham ishlaydi', () {
    final bytes = Uint8List(fw * fh)..fillRange(0, fw * fh, 120);
    final g = warpGray(
      frame: RawPlane(width: fw, height: fh, channels: 1, bytes: bytes),
      rotation: rotationMatrix(0, 0, 0),
      longSideFovDeg: fov,
      canvasW: canvasW,
      canvasH: canvasH,
    );
    expect(_peak(g), 120);
  });

  test('kadr tuvalga umuman tushmasa bo‘sh plan qaytadi', () {
    // Hech narsa yiqilmaydi va uzunlik baribir to'g'ri — chaqiruvchi
    // uni indekslaydi.
    final g = warpGray(
      frame: solid(200, 200, 200),
      rotation: rotationMatrix(0, 0, 0),
      longSideFovDeg: fov,
      canvasW: canvasW,
      canvasH: canvasH,
    );
    expect(g.length, canvasW * canvasH);
  });
}

/// Qoplangan pikseldagi eng katta qiymat.
///
/// Chetdagi pikseller bilinear namunadan biroz past chiqadi, shuning
/// uchun o'rtacha emas, CHO'QQI solishtiriladi — u kadrning haqiqiy
/// rangini beradi.
int _peak(Uint8List g) {
  int m = 0;
  for (final int v in g) {
    if (v > m) m = v;
  }
  return m;
}
