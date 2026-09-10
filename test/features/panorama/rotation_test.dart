import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/math/rotation.dart';

/// Butun tikish quvurining POYDEVORI shu yerda qotiriladi.
///
/// Proyektor bu matritsani TRANSPOZ qilib teskarilaydi, va transpoz faqat
/// matritsa ortonormal bo'lgandagina teskari bo'ladi. Manbada u bir vaqtlar
/// ortonormal EMAS edi — o'rta ustunning belgilari xato edi — va natija
/// ko'rinadigan crash emas, jimgina gorizontga siqilgan panorama bo'lgan:
/// o'sha kadrlar 138° berishi kerak bo'lgan joyda 67° qamrov o'lchangan.
///
/// Shu sababli bu yerdagi testlar «shunday ishlaydi» ni emas, «shu buzilsa
/// keyingi 16 qadam sababsiz ishlamaydi» ni qo'riqlaydi.
void main() {
  double rad(double deg) => deg * math.pi / 180;

  /// i- va j-ustunlarning skalyar ko'paytmasi (qator-major 3x3).
  double dot(List<double> m, int c1, int c2) =>
      m[c1] * m[c2] + m[3 + c1] * m[3 + c2] + m[6 + c1] * m[6 + c2];

  /// 2-ustun — linza dunyoda qayerga qarayotgani.
  (double lat, double lon) forward(List<double> m) {
    final double x = m[2], y = m[5], z = m[8];
    return (math.asin(y.clamp(-1.0, 1.0)), math.atan2(x, z));
  }

  group('rotationMatrix', () {
    // (a) ENG MUHIM TEST. `dot(col1, col2) == 0` — o'rta ustundagi ikki minus
    // olib tashlansa AYNAN shu yiqiladi.
    test('suratga olish ishlatadigan hamma burchaklarda ortonormal', () {
      for (final double yaw in <double>[0, 37, 90, 180, 271, 359]) {
        for (final double pitch in <double>[-90, -45, -12, 0, 12, 45, 90]) {
          for (final double roll in <double>[-30, 0, 30]) {
            final Float64List m = rotationMatrix(
              rad(yaw),
              rad(pitch),
              rad(roll),
            );
            final String at = 'yaw=$yaw pitch=$pitch roll=$roll';
            for (int c = 0; c < 3; c++) {
              expect(
                dot(m, c, c),
                closeTo(1, 1e-9),
                reason: '$c-ustun birlik emas: $at',
              );
            }
            expect(dot(m, 0, 1), closeTo(0, 1e-9), reason: 'x.y: $at');
            expect(dot(m, 0, 2), closeTo(0, 1e-9), reason: 'x.z: $at');
            expect(
              dot(m, 1, 2),
              closeTo(0, 1e-9),
              reason: '«yuqori» va «oldinga» perpendikulyar emas: $at',
            );
          }
        }
      }
    });

    // (b)
    test('nolda identity — kamera +Z ga qaraydi', () {
      final Float64List m = rotationMatrix(0, 0, 0);
      expect(m.toList(), <double>[1, 0, 0, 0, 1, 0, 0, 0, 1]);
    });

    // (c) lon = atan2(r2, r8) == yaw
    test('yaw ko\'rinishni longitudada buradi, latitude\'ga tegmaydi', () {
      for (final double yaw in <double>[0, 45, 90, 180, 300]) {
        final (double lat, double lon) = forward(rotationMatrix(rad(yaw), 0, 0));
        expect(lat, closeTo(0, 1e-9));
        // cos(farq) bilan tekshiriladi, chunki 300° va −60° bir xil longitude.
        expect(
          math.cos(lon - rad(yaw)),
          closeTo(1, 1e-9),
          reason: 'yaw $yaw longitude $yaw ni ko\'rsatishi kerak',
        );
      }
    });

    // (c) lat = asin(r5) == pitch
    test('musbat pitch ko\'rinishni ko\'taradi', () {
      for (final double pitch in <double>[-45, -20, 0, 20, 45]) {
        final (double lat, double _) = forward(rotationMatrix(0, rad(pitch), 0));
        expect(lat * 180 / math.pi, closeTo(pitch, 1e-9));
      }
    });

    test('tik yuqoriga qaralganda ko\'rinish qutbda', () {
      final (double lat, double _) = forward(rotationMatrix(0, rad(90), 0));
      expect(lat * 180 / math.pi, closeTo(90, 1e-9));
      final (double latDown, double _) = forward(rotationMatrix(0, rad(-90), 0));
      expect(latDown * 180 / math.pi, closeTo(-90, 1e-9));
    });

    // (d)
    test('roll kadrni aylantiradi, lekin qayerga qarashini O\'ZGARTIRMAYDI', () {
      final (double lat0, double lon0) = forward(
        rotationMatrix(rad(70), rad(25), 0),
      );
      for (final double roll in <double>[-40, 15, 90]) {
        final (double lat, double lon) = forward(
          rotationMatrix(rad(70), rad(25), rad(roll)),
        );
        expect(lat, closeTo(lat0, 1e-9), reason: 'roll $roll');
        expect(lon, closeTo(lon0, 1e-9), reason: 'roll $roll');
      }
    });
  });

  group('kamera konvensiyasi', () {
    const double cx = 500, cy = 900, f = 1335;

    // (e)
    test('piksel → nur → piksel aylanmasi aynan identity', () {
      for (final (double px, double py) in <(double, double)>[
        (500, 900),
        (0, 0),
        (999, 1799),
        (120, 1500),
        (880, 250),
      ]) {
        final Float64List v = cameraRayFromPixel(px, py, cx, cy, f);
        final Float64List back = pixelFromCameraRay(v, cx, cy, f);
        expect(back[0], closeTo(px, 1e-9), reason: 'x: ($px, $py)');
        expect(back[1], closeTo(py, 1e-9), reason: 'y: ($px, $py)');
      }
    });

    test('nurlar birlik uzunlikda va oldinga qaraydi', () {
      final Float64List v = cameraRayFromPixel(100, 200, cx, cy, f);
      expect(
        math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]),
        closeTo(1, 1e-12),
      );
      expect(v[2], greaterThan(0), reason: 'kamera +Z ga qaraydi');
    });

    // (f) O'lchangan belgi: bu kombinatsiyada qoldiq 2.9°, qolgan uchtasida
    // 37° / 43° / 30°.
    test('tizim o\'ng qo\'l: kamera X o\'qi CHAPGA qaraydi', () {
      final Float64List right = cameraRayFromPixel(cx + 200, cy, cx, cy, f);
      expect(right[0], lessThan(0), reason: 'markazdan O\'NGDAGI piksel');
      final Float64List left = cameraRayFromPixel(cx - 200, cy, cx, cy, f);
      expect(left[0], greaterThan(0), reason: 'markazdan CHAPDAGI piksel');
      final Float64List below = cameraRayFromPixel(cx, cy + 200, cx, cy, f);
      expect(below[1], lessThan(0), reason: 'markazdan PASTDAGI piksel');
      final Float64List above = cameraRayFromPixel(cx, cy - 200, cx, cy, f);
      expect(above[1], greaterThan(0), reason: 'markazdan YUQORIDAGI piksel');
    });

    test('kadr markazi — optik o\'qning o\'zi', () {
      final Float64List v = cameraRayFromPixel(cx, cy, cx, cy, f);
      expect(v[0], closeTo(0, 1e-12));
      expect(v[1], closeTo(0, 1e-12));
      expect(v[2], closeTo(1, 1e-12));
    });
  });

  group('placementLon', () {
    // (g)
    test('yo\'nalishga TESKARI yuradi', () {
      expect(placementLon(0), 0);
      expect(placementLon(90), closeTo(-math.pi / 2, 1e-12));
      expect(placementLon(-90), closeTo(math.pi / 2, 1e-12));
    });

    test('kadr yo\'nalishi aytgan joyga tushadi (ichkaridan qaralganda)', () {
      // Telefonni o'ngga 30° burish kadrning optik o'qini 30° ga siljitishi
      // shart — longitude qaysi tomonga sanalishidan qat'i nazar.
      final Float64List a = rotationMatrix(placementLon(0), 0, 0);
      final Float64List b = rotationMatrix(placementLon(30), 0, 0);
      final double d = a[2] * b[2] + a[5] * b[5] + a[8] * b[8];
      expect(math.acos(d.clamp(-1.0, 1.0)) * 180 / math.pi, closeTo(30, 1e-9));
    });

    // (h) 12° qadamli 30 kadrli halqa, WRAP bilan birga. Belgi xatosi bitta
    // juftlik uchun to'g'ri, butun halqa uchun xato bo'lib qoladi — shuning
    // uchun o'ralish joyi ham tekshiriladi.
    test('qo\'shni kadrlar butun halqa bo\'ylab qo\'shni bo\'lib qoladi', () {
      for (final (double from, double to) in <(double, double)>[
        (0, 12),
        (180, 192),
        (348, 360),
        (354, 6),
      ]) {
        final Float64List a = rotationMatrix(placementLon(from), 0, 0);
        final Float64List b = rotationMatrix(placementLon(to), 0, 0);
        final double d = a[2] * b[2] + a[5] * b[5] + a[8] * b[8];
        expect(
          math.acos(d.clamp(-1.0, 1.0)) * 180 / math.pi,
          closeTo(12, 1e-9),
          reason: '$from → $to',
        );
      }
    });
  });

  group('fokus va ko\'rish burchagi', () {
    // (k) ⚠️ Bu raqamlar QAYTA HISOBLANGAN. Rejaning va manbaning matnida
    // uchraydigan 2882.3 / 2884.6 / 41.10 — XATO.
    test('focalPx 4K uzun tomon uchun 2884.37 px', () {
      expect(focalPx(2160, 3840, 67.3), closeTo(2884.37, 0.01));
      // Uzun tomon O'ZI tanlanadi: portret va landshaft bir xil focal beradi.
      // Aks holda EXIF orientatsiyasi ~1.78× xato beradi va hech narsa
      // tikilmaydi (reja §4.2).
      expect(focalPx(3840, 2160, 67.3), closeTo(focalPx(2160, 3840, 67.3), 0));
      expect(focalPx(2160, 3840, 67.3) / 3840, closeTo(0.7511376, 1e-7));
    });

    test('hFovDeg yarim kenglik 1080 va shu focal uchun 41.055°', () {
      expect(hFovDeg(1080, 2884.37), closeTo(41.055, 0.01));
      // Manbadagi `_hFovDeg(w, h, fov)` shu ikkovining kompozitsiyasi.
      expect(
        hFovDeg(2160 / 2, focalPx(2160, 3840, 67.3)),
        closeTo(41.055, 0.01),
      );
      // Uzun tomon bo'yicha olinsa — kiritilgan FOV ning o'zi qaytadi.
      expect(
        hFovDeg(3840 / 2, focalPx(2160, 3840, 67.3)),
        closeTo(67.3, 1e-9),
      );
    });
  });
}
