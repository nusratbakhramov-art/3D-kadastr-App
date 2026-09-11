import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/widgets/media_upload_row.dart';

/// Eskiz TARMOQDAN yuklanishi kerak, agar yozuv lokal fayl bo'lmasa.
///
/// ⚠️ NEGA SHU TEST BOR. 360° panorama endi SERVERDA tikiladi: sehrgar
/// lokal JPEG emas, S3 KALITI (`listings/media/3/pano_7.jpg`) saqlaydi va
/// kadrlar darhol o'chiriladi. Qator esa eskizni `Image.file` bilan
/// chizardi — natijada tayyor panorama «hujjat» ikonkasi bo'lib ko'rinardi
/// va foydalanuvchi yuklanmagan deb o'ylardi. Bu jimgina buziladi:
/// analyze ham, boshqa testlar ham buni ushlamaydi.
void main() {
  const key = 'listings/media/3/pano_7_1789.jpg';

  Future<void> pump(
    WidgetTester tester, {
    String? Function(String)? urlOf,
    String path = key,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaUploadRow(
          label: '360',
          iconAsset: 'assets/icons/upload-360.svg',
          paths: <String>[path],
          urlOf: urlOf,
          onAdd: () {},
          onRemove: (_) {},
        ),
      ),
    ),
  );

  ImageProvider providerOf(WidgetTester tester) =>
      tester.widget<Image>(find.byType(Image)).image;

  testWidgets('URL berilsa eskiz TARMOQDAN olinadi', (tester) async {
    await pump(tester, urlOf: (k) => 'https://cdn.test/$k');

    final p = providerOf(tester);
    expect(p, isA<NetworkImage>());
    expect((p as NetworkImage).url, 'https://cdn.test/$key');
  });

  testWidgets('URL yo\'q — eskiz LOKAL fayldan olinadi', (tester) async {
    await pump(tester, path: '/tmp/photo.jpg');

    expect(providerOf(tester), isA<FileImage>());
  });

  testWidgets('URL bo\'sh satr — lokal faylga tushadi', (tester) async {
    // `PanoOutcome.url` server manzil qaytarmasa bo'sh bo'lishi mumkin;
    // bo'sh manzil bilan `Image.network` darhol yiqiladi.
    await pump(tester, urlOf: (_) => '');

    expect(providerOf(tester), isA<FileImage>());
  });
}
