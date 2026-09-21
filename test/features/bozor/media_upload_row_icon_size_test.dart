import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/screens/bozor_description_step_screen.dart';
import 'package:kadastr/features/bozor/widgets/media_upload_row.dart';

/// 360° ikonkasi qolganlaridan KICHIKROQ (PANO-04).
///
/// ⚠️ NEGA TEST. `upload-360.svg` yagona YOTIQ ikonka (21 × 14.9): bir xil
/// kvadratga sig'dirilganda u foto/planirovka ikonkalaridan kengroq
/// ko'rinadi. O'lcham endi qatorga uzatiladi, ya'ni uni tasodifan qaytarib
/// qo'yish oson — shuning uchun qulflab qo'yamiz. Simulyatorda bu qatorni
/// ko'rib bo'lmaydi: u faqat qurilmada 360° capture mavjud bo'lganda
/// chiziladi.
void main() {
  double iconWidth(WidgetTester tester) => tester
      .widget<SvgPicture>(find.byType(SvgPicture))
      .width!;

  testWidgets('sukut o\'lchami — 26', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaUploadRow(
            label: 'Foto',
            iconAsset: 'assets/icons/upload-photo.svg',
            paths: const <String>[],
            onAdd: () {},
            onRemove: (_) {},
          ),
        ),
      ),
    );
    expect(iconWidth(tester), 26);
  });

  testWidgets('berilgan o\'lcham qo\'llanadi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaUploadRow(
            label: '360',
            iconAsset: 'assets/icons/upload-360.svg',
            iconSize: 22,
            paths: const <String>[],
            onAdd: () {},
            onRemove: (_) {},
          ),
        ),
      ),
    );
    expect(iconWidth(tester), 22);
  });

  testWidgets('Tavsif qadamida 360° qatori kichikroq ikonka bilan quriladi', (
    tester,
  ) async {
    final draft = BozorDraft(
      deal: DealType.rent,
      kind: PropertyKind.residential,
      type: PropertyType.apartment,
    );
    // Qator faqat panorama bor (yoki capture mavjud) bo'lganda chiziladi.
    draft.description.panoramas.add('listings/media/1/pano_1.jpg');

    await tester.pumpWidget(
      MaterialApp(home: BozorDescriptionStepScreen(draft: draft)),
    );
    await tester.pump();

    final rows = tester
        .widgetList<MediaUploadRow>(find.byType(MediaUploadRow))
        .toList();
    final pano = rows.singleWhere(
      (r) => r.iconAsset == 'assets/icons/upload-360.svg',
    );
    final photo = rows.singleWhere(
      (r) => r.iconAsset == 'assets/icons/upload-photo.svg',
    );
    expect(
      pano.iconSize,
      lessThan(photo.iconSize),
      reason: '360° ikonkasi foto ikonkasidan kichikroq bo\'lishi kerak',
    );
    // Ekran tarmoq/kanal taymerlarini boshlaydi — testni toza yopamiz.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
