/// Capture kompasi: har qator uchun bitta konsentrik halqa, har nuqta —
/// rejadagi bitta surat, olingani to'ldiriladi, jonli yo'nalish esa strelka.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../models/capture_ring.dart';

/// Olingan kadr nuqtasi — brend yashili.
const Color kTakenDot = AppColors.splashGreen;

/// Jonli yo'nalish strelkasi.
///
/// Uy palitrasida mos rang yo'q: bu ilova bezagi emas, qora fon ustidagi
/// FUNKSIONAL ko'rsatkich va u yashil nuqtalardan aniq ajralib turishi
/// kerak — aks holda strelka olingan kadr bilan chalkashadi.
const Color kNeedle = Color(0xFF38BDF8);

/// Kompasning bitta halqasi: qaysi qator, qanday radiusda, faolmi.
@immutable
class DialSlot {
  const DialSlot({
    required this.row,
    required this.radius,
    required this.active,
  });

  /// `ring.rows` dagi ASL indeks — ustunlar soni, `yawOf` va `isTaken`
  /// shuni oladi.
  final int row;

  /// Markazdan masofa.
  final double radius;

  /// Telefon hozir shu qatorda ushlab turilganmi.
  final bool active;
}

/// Kompas joylashuvi — SOF funksiya.
///
/// Ataylab ajratilgan: bu yerda `slot` (markazdan qaysi masofada) va `row`
/// (`ring.rows` dagi asl indeks) ni adashtirish eng oson xato, va rassom
/// ichida qolganda uni test bilan ushlab bo'lmasdi.
///
/// Qatorlar YUQORIDAN qaralgandek: qator qanchalik yuqoriga qarasa,
/// markazga shunchalik yaqin — yuqoriga qarash zenitga yaqinlashgani kabi.
@visibleForTesting
List<DialSlot> dialSlots(List<CaptureRow> rows, double outer, int? activeRow) {
  // ⚠️ `outer` MANFIY bo'lishi mumkin: chaqiruvchi uni
  // `shortestSide / 2 - 10` dan hisoblaydi va 20 dan kichik o'lchamda
  // (bo'sh constraint, widget test) bu manfiy chiqadi. Manfiy radius bilan
  // `drawCircle` istisno TASHLAMAYDI — u jimgina g'alati narsa chizadi,
  // ya'ni nosozlik faqat ko'z bilan ko'rinardi. Shu yerda to'xtatiladi.
  if (outer <= 0) return const <DialSlot>[];
  // ⚠️ INDEKS RO'YXATI saralanadi, `rows` NING O'ZI EMAS.
  //
  // Ikki sabab. Birinchisi qat'iy: `CaptureRing.rows` sukut bo'yicha
  // `const List<CaptureRow>`, ya'ni uni JOYIDA saralash `UnsupportedError`
  // tashlaydi.
  //
  // Ikkinchisi kelajak uchun: nusxani saralab keyin `indexOf` bilan indeks
  // izlash BUGUN ishlaydi, chunki `CaptureRow` da `==` yo'q va `indexOf`
  // AYNIYAT bo'yicha solishtiradi. Lekin `CaptureRow` ga `==` qo'shilishi
  // (qiymat sinfi uchun tabiiy narsa) o'sha yondashuvni jimgina buzardi:
  // bir xil pitch va shotCount'li ikki qator bir-biriga teng bo'lib qolardi
  // va ikkalasi ham BIRINCHISINING indeksini olardi. Indeks ro'yxati bunga
  // umuman bog'liq emas.
  final List<int> byPitch = <int>[for (int i = 0; i < rows.length; i++) i]
    ..sort((int a, int b) => rows[b].pitchDeg.compareTo(rows[a].pitchDeg));

  return <DialSlot>[
    for (int slot = 0; slot < byPitch.length; slot++)
      DialSlot(
        row: byPitch[slot],
        radius: byPitch.length == 1
            ? outer
            // Bitta qatorda `byPitch.length - 1` nol bo'lardi.
            : outer * (0.45 + 0.55 * slot / (byPitch.length - 1)),
        // ⚠️ `row`, `slot` EMAS. `defaultRows` bilan faol qator 0
        // (gorizont) 2-slotda turadi — `slot == activeRow` yozilsa zenit
        // halqasi yonardi.
        active: byPitch[slot] == activeRow,
      ),
  ];
}

class RingDial extends StatelessWidget {
  const RingDial({
    super.key,
    required this.ring,
    required this.relativeYaw,
    this.activeRow,
    this.size = 150,
  });

  final CaptureRing ring;

  /// Telefon qayerga qaragan — BIRINCHI kadrga nisbatan, gradusda.
  final double relativeYaw;

  /// Telefon hozir ushlab turilgan qator, agar aniq bo'lsa.
  final int? activeRow;

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DialPainter(
          ring: ring,
          yaw: relativeYaw,
          activeRow: activeRow,
          // ⚠️ SANOQ SHU YERDA SURATGA OLINADI — `shouldRepaint` dagi
          // xatoni tuzatish uchun. Pastdagi izohga qara.
          takenAtBuild: ring.takenCount,
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.ring,
    required this.yaw,
    required this.activeRow,
    required this.takenAtBuild,
  });

  final CaptureRing ring;
  final double yaw;
  final int? activeRow;

  /// Widget qurilgan paytdagi olingan kadrlar soni.
  final int takenAtBuild;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    // ⚠️ Manbada bu shunchaki `size.shortestSide / 2 - 10` edi va 20 dan
    // kichik o'lchamda MANFIY chiqardi (bo'sh constraint'da widget test
    // ostida ham). Manfiy radius bilan chizish jim g'alati natija beradi.
    final double outer = math.max(0, size.shortestSide / 2 - 10);
    if (outer <= 0) return;

    for (final DialSlot s in dialSlots(ring.rows, outer, activeRow)) {
      final int row = s.row;
      final double radius = s.radius;
      final bool active = s.active;

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          // ⚠️ `2.0 : 1.0`, `2 : 1` emas. Bu yerda `int` literal `double`
          // kontekstida turgani uchun kompilyatsiya bo'ladi; ifodani
          // `final` lokalga chiqarsangiz u `int` bo'lib qoladi va
          // `strokeWidth` ga tushmaydi.
          ..strokeWidth = active ? 2.0 : 1.0
          ..color = Colors.white.withValues(alpha: active ? 0.4 : 0.14),
      );

      for (int column = 0; column < ring.rows[row].shotCount; column++) {
        // Ekran noli TEPADA va burchaklar soat yo'nalishida o'sadi —
        // shuning uchun −90.
        final double rad =
            (ring.yawOf(ShotId(row, column)) - 90) * math.pi / 180;
        final Offset at =
            centre + Offset(math.cos(rad), math.sin(rad)) * radius;
        final bool taken = ring.isTaken(ShotId(row, column));
        canvas.drawCircle(
          at,
          taken ? 4.5 : 3.0,
          Paint()
            ..color = taken
                ? kTakenDot
                : Colors.white.withValues(alpha: active ? 0.5 : 0.25),
        );
      }
    }

    // ⚠️ CHIZISH TARTIBI MUHIM: avval hamma halqa va nuqta, keyin strelka,
    // eng oxirida markaz. Strelka nuqtalar USTIDA, markaz esa strelkaning
    // uchini yopadi. Tartibni o'zgartirish ko'rinishni jimgina buzadi.
    final double needle = (yaw - 90) * math.pi / 180;
    canvas
      ..drawLine(
        centre,
        centre + Offset(math.cos(needle), math.sin(needle)) * outer,
        Paint()
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = kNeedle,
      )
      ..drawCircle(centre, 3.5, Paint()..color = kNeedle);
  }

  /// ⚠️ MANBADAGI XATO TUZATILDI.
  ///
  /// Manbada bu shart `old.ring.takenCount != ring.takenCount` edi. Capture
  /// ekrani BITTA o'zgaruvchan `CaptureRing` nusxasini beradi, ya'ni
  /// `old.ring` va `ring` — AYNI OBYEKT va shart HECH QACHON rost
  /// bo'lmaydi. Yangi kadr olinganda kompas o'zi qayta chizilmasdi.
  ///
  /// Amalda u ko'pincha baribir qayta chizilardi, chunki `yaw` doim
  /// o'zgaradi — lekin AYNAN zatvor ochiladigan payt bundan mustasno:
  /// kadr olinishi uchun telefon QIMIRLAMASLIGI shart, ya'ni `yaw` ham
  /// qotgan bo'ladi. Ya'ni yangi yashil nuqta aynan u paydo bo'lishi
  /// kerak bo'lgan lahzada ko'rinmasdi.
  ///
  /// Tuzatish: sanoq `build` paytida suratga olinadi
  /// ([takenAtBuild]) va shu solishtiriladi.
  @override
  bool shouldRepaint(_DialPainter old) =>
      old.yaw != yaw ||
      old.activeRow != activeRow ||
      old.takenAtBuild != takenAtBuild;
}
