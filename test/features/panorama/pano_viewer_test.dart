import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/screens/pano_viewer_screen.dart';

/// Sfera proyeksiyasi — 360° ko'ruvchining butun geometriyasi.
///
/// Bu yerdagi xatolarning HAMMASI jim: tasvir ko'zguda chiqadi, tepa
/// bilan past almashadi yoki chokda surtiladi — kompilyator hech narsa
/// demaydi. Shuning uchun har da'vo aniq son bilan qotirilgan.
void main() {
  const Size size = Size(400, 800);
  const int imgW = 3072;
  const int imgH = 1536;

  SphereMesh mesh({
    double yaw = 0,
    double pitch = 0,
    double fov = kInitialFovDeg,
  }) => projectSphere(
    size: size,
    yawDeg: yaw,
    pitchDeg: pitch,
    fovDeg: fov,
    imageW: imgW,
    imageH: imgH,
  )!;

  /// Ekran markaziga ENG YAQIN tugunning tekstura koordinatasi.
  ///
  /// Ya'ni «hozir qaerga qarayapmiz» degan savolning javobi, tasvir
  /// piksellarida.
  (double u, double v) atCentre(SphereMesh m) {
    final centre = Offset(size.width / 2, size.height / 2);
    double best = double.infinity;
    int bestK = 0;
    for (int k = 0; k < m.vertexCount; k++) {
      final double x = m.positions[k * 2];
      final double y = m.positions[k * 2 + 1];
      // Ko'rinmagan tugun `(0, 0)` bo'lib qoladi — uni hisobga olmaymiz.
      if (x == 0 && y == 0) continue;
      final double d = (Offset(x, y) - centre).distanceSquared;
      if (d < best) {
        best = d;
        bestK = k;
      }
    }
    return (m.texCoords[bestK * 2], m.texCoords[bestK * 2 + 1]);
  }

  group('qayerga qaraymiz', () {
    test('yaw 0 — tasvirning CHAP cheti markazda', () {
      // Ekvirektangulyarda `lon = 0` tasvirning chap cheti. Ko'ruvchi
      // ham shu yerdan boshlanadi, aks holda «0°» ikki joyda ikki xil
      // narsani anglatardi.
      final (double u, double v) = atCentre(mesh());
      expect(u, closeTo(0, imgW / _cols));
      expect(v, closeTo(imgH / 2, imgH / _rows), reason: 'gorizont o‘rtada');
    });

    test('yaw 90 — tasvirning CHORAGIGA suriladi', () {
      final (double u, _) = atCentre(mesh(yaw: 90));
      expect(u, closeTo(imgW / 4, imgW / _cols));
    });

    test('yaw KO‘PAYSA — o‘ngga, ya‘ni u ham ko‘payadi', () {
      // Belgi almashsa panorama KO'ZGUDA ko'rinardi va buni faqat
      // tanish joyni ko'rib bilish mumkin bo'lardi.
      final (double a, _) = atCentre(mesh(yaw: 30));
      final (double b, _) = atCentre(mesh(yaw: 60));
      expect(b, greaterThan(a));
    });

    test('pitch MUSBAT — YUQORIGA, ya‘ni v kamayadi', () {
      // Ekvirektangulyarda `v = 0` — ZENIT. Belgi almashsa tepa bilan
      // past almashardi.
      final (_, double up) = atCentre(mesh(pitch: 45));
      final (_, double mid) = atCentre(mesh());
      final (_, double down) = atCentre(mesh(pitch: -45));
      expect(up, lessThan(mid));
      expect(down, greaterThan(mid));
    });
  });

  group('proyeksiya', () {
    // ⚠️ MARKAZ IKKALA BELGI ALMASHGANDA HAM JOYIDA QOLADI. Ya'ni
    // «markazda nima ko'rinadi» degan tekshiruvlar ko'zguni ham,
    // ag'darilgan tasvirni ham TUTMAYDI — ular markazning qo'zg'almas
    // nuqta ekanini o'zgartirmaydi. Belgilarni faqat YON tomondagi
    // tugun qotiradi.
    const int cols = _cols + 1;

    test('lon KO‘PAYSA ekranda O‘NGGA — tasvir KO‘ZGU emas', () {
      final SphereMesh m = mesh();
      // `lat = 0`, `lon = +11.25°` — markazdan o'ngda bo'lishi shart.
      const int k = (_rows ~/ 2) * cols + 3;
      expect(m.positions[k * 2], greaterThan(size.width / 2));
      expect(m.positions[k * 2 + 1], closeTo(size.height / 2, 0.5));
    });

    test('lat KO‘PAYSA ekranda YUQORIGA — tasvir AG‘DARILMAGAN', () {
      final SphereMesh m = mesh();
      // `lon = 0`, `lat = +11.25°` — markazdan tepada bo'lishi shart.
      const int k = (_rows ~/ 2 - 3) * cols;
      expect(m.positions[k * 2 + 1], lessThan(size.height / 2));
      expect(m.positions[k * 2], closeTo(size.width / 2, 0.5));
    });

    test('qarayotgan nuqta AYNAN ekran markazida', () {
      final SphereMesh m = mesh(yaw: 90);
      // `lon = 90°`, `lat = 0` tuguni — u to'rda aniq mavjud.
      const int j = _rows ~/ 2;
      const int i = _cols ~/ 4;
      const int k = j * (_cols + 1) + i;
      expect(m.positions[k * 2], closeTo(size.width / 2, 0.5));
      expect(m.positions[k * 2 + 1], closeTo(size.height / 2, 0.5));
    });

    test('FOV kichraysa manzara KATTALASHADI', () {
      // Bir xil ikki tugun orasidagi ekran masofasi ortishi kerak.
      double span(double fov) {
        final SphereMesh m = mesh(fov: fov);
        const int j = _rows ~/ 2;
        const int k0 = j * (_cols + 1);
        const int k1 = k0 + 1;
        return (m.positions[k1 * 2] - m.positions[k0 * 2]).abs();
      }

      expect(span(30), greaterThan(span(90)));
    });

    test('orqadagi tugunlar chizilmaydi', () {
      final SphereMesh m = mesh();
      // Orqaga qaragan nuqta (`lon = 180°`) hech qaysi uchburchakka
      // kirmasligi kerak: u kamera tekisligining narigi tomonida va
      // proyeksiyasi ma'nosiz.
      const int j = _rows ~/ 2;
      const int k = j * (_cols + 1) + _cols ~/ 2;
      expect(m.indices.contains(k), isFalse);
    });

    test('ko‘rinadigan uchburchaklar BOR va hammasi to‘rda', () {
      final SphereMesh m = mesh();
      expect(m.triangleCount, greaterThan(100));
      for (final int k in m.indices) {
        expect(k, lessThan(m.vertexCount));
      }
    });
  });

  group('chok', () {
    test('tekstura koordinatasi to‘r bo‘ylab MONOTON — sakrash yo‘q', () {
      // BUTUN sabab shu. Ekran to'ri bilan qilinganda chokni kesgan
      // uchburchakda `u` 3071 dan 0 ga sakraydi va Skia oradagi hamma
      // narsani teskarisiga surtib yuboradi. Sfera to'rida `lon = 0`
      // va `lon = 2π` AYRIM tugunlar, ya'ni sakrash yuzaga kelmaydi.
      final SphereMesh m = mesh();
      const int cols = _cols + 1;
      for (int j = 0; j < _rows + 1; j++) {
        for (int i = 0; i < _cols; i++) {
          final double a = m.texCoords[(j * cols + i) * 2];
          final double b = m.texCoords[(j * cols + i + 1) * 2];
          expect(b, greaterThan(a), reason: 'u kamaydi: ($i, $j)');
        }
      }
    });

    test('u ayni 0 dan imageW gacha boradi', () {
      final SphereMesh m = mesh();
      const int cols = _cols + 1;
      expect(m.texCoords[0], 0);
      expect(m.texCoords[(cols - 1) * 2], closeTo(imgW.toDouble(), 1e-6));
    });

    test('chokni KESIB qaraganda ham uchburchak topiladi', () {
      // `yaw = 0` da ko'rish maydoni chokning ikki tomonida yotadi.
      final SphereMesh m = mesh();
      final double left = m.texCoords[m.indices.first * 2];
      expect(m.triangleCount, greaterThan(100));
      expect(left, isNot(isNaN));
    });
  });

  group('chegaralar', () {
    test('QUTBGA aynan yetkazilmaydi', () {
      // `pitch = ±90` da o'ng tomon vektori nolga aylanadi va tasvir
      // bir kadrga aylanib ketardi. Qisish shu uchun.
      for (final double p in <double>[90, -90, 200, -200]) {
        final SphereMesh? m = projectSphere(
          size: size,
          yawDeg: 0,
          pitchDeg: p,
          fovDeg: kInitialFovDeg,
          imageW: imgW,
          imageH: imgH,
        );
        expect(m, isNotNull, reason: 'pitch $p da yiqildi');
        expect(m!.triangleCount, greaterThan(0));
        for (int k = 0; k < m.vertexCount * 2; k++) {
          expect(m.positions[k].isFinite, isTrue, reason: 'pitch $p');
        }
      }
    });

    test('yaw AYLANADI — 0 va 360 bir xil manzara', () {
      final (double a, _) = atCentre(mesh(yaw: 0));
      final (double b, _) = atCentre(mesh(yaw: 360));
      expect(b, closeTo(a, imgW / _cols));
    });

    test('bo‘sh o‘lcham — null, yiqilmaydi', () {
      expect(
        projectSphere(
          size: Size.zero,
          yawDeg: 0,
          pitchDeg: 0,
          fovDeg: kInitialFovDeg,
          imageW: imgW,
          imageH: imgH,
        ),
        isNull,
      );
    });

    test('hamma koordinata CHEKLI — NaN yo‘q', () {
      for (final double yaw in <double>[0, 45, 179, 180, 181, 359]) {
        final SphereMesh m = mesh(yaw: yaw, pitch: 60);
        for (int k = 0; k < m.vertexCount; k++) {
          expect(m.texCoords[k * 2].isFinite, isTrue);
          expect(m.texCoords[k * 2 + 1].isFinite, isTrue);
        }
        for (final int k in m.indices) {
          expect(m.positions[k * 2].isFinite, isTrue, reason: 'yaw $yaw');
          expect(m.positions[k * 2 + 1].isFinite, isTrue, reason: 'yaw $yaw');
        }
      }
    });

    test('indekslar Uint16 ga SIG‘ADI', () {
      // `Vertices.raw` indekslarni `Uint16List` da kutadi, ya'ni
      // to'r 65 535 tugundan oshmasligi kerak. Zichlikni oshirish
      // shu chegarani jimgina buzishi mumkin edi.
      expect((_cols + 1) * (_rows + 1), lessThan(1 << 16));
    });
  });

  test('to‘r ZICH — affin interpolyatsiya xatosi KO‘RINMAYDI', () {
    // `drawVertices` teksturani AFFIN interpolyatsiya qiladi: uchburchak
    // ichida ekran nuqtasi bilan tekstura nuqtasi chiziqli bog'lanadi,
    // haqiqiy proyeksiya esa chiziqli EMAS. Xato to'r zichligiga bog'liq
    // va uni PIKSELDA o'lchash mumkin — «uchburchak necha piksel» degan
    // bilvosita o'lchov emas.
    //
    // Usul: qo'shni ikki tugunning ekrandagi o'rtasi (affin taxmin) va
    // aynan o'rtadagi burchakning haqiqiy proyeksiyasi solishtiriladi.
    // Ikki barobar zich to'r haqiqiy javobni beradi.
    const int cols = _cols + 1;
    const int fineCols = _cols * 2 + 1;

    for (final double fov in <double>[kMinFovDeg, kInitialFovDeg, kMaxFovDeg]) {
      final SphereMesh coarse = mesh(fov: fov);
      final SphereMesh fine = projectSphere(
        size: size,
        yawDeg: 0,
        pitchDeg: 0,
        fovDeg: fov,
        imageW: imgW,
        imageH: imgH,
        lonSteps: _cols * 2,
      )!;

      final Set<int> drawn = coarse.indices.toSet();

      // ⚠️ FAQAT EKRANDAGI tugunlar. To'r ko'rish o'qidan 89° gacha
      // cho'ziladi va o'sha tugunlar ekrandan o'n minglab piksel
      // uzoqqa proyeksiya qilinadi — ularning affin xatosi ham
      // o'n minglab piksel, lekin Skia ularni kesib tashlaydi va
      // foydalanuvchi hech qachon ko'rmaydi. Ularni o'lchash
      // ko'rinmaydigan narsani o'lchash bo'lardi.
      bool onScreen(int k) {
        final double x = coarse.positions[k * 2];
        final double y = coarse.positions[k * 2 + 1];
        return x >= 0 && y >= 0 && x <= size.width && y <= size.height;
      }

      double worst = 0;
      for (int j = 0; j < _rows + 1; j++) {
        for (int i = 0; i < _cols; i++) {
          final int a = j * cols + i;
          final int b = a + 1;
          if (!drawn.contains(a) || !drawn.contains(b)) continue;
          if (!onScreen(a) || !onScreen(b)) continue;

          final double mx =
              (coarse.positions[a * 2] + coarse.positions[b * 2]) / 2;
          final double my =
              (coarse.positions[a * 2 + 1] + coarse.positions[b * 2 + 1]) / 2;

          final int f = j * fineCols + i * 2 + 1;
          final double dx = mx - fine.positions[f * 2];
          final double dy = my - fine.positions[f * 2 + 1];
          final double err = dx * dx + dy * dy;
          if (err > worst) worst = err;
        }
      }
      // Bir pikseldan kam — ekranda ko'rinmaydi.
      expect(
        math.sqrt(worst),
        lessThan(1.0),
        reason: 'FOV $fov da affin xatosi sezilarli',
      );
    }
  });
}

/// Sukut bo'yicha to'r zichligi — `projectSphere` ning standart qiymati.
///
/// Testda takrorlangani ataylab: zichlik o'zgarsa bu yerdagi indeks
/// hisoblari ham o'zgarishi kerak va test buni DARHOL aytadi.
const int _cols = 96;
const int _rows = 48;
