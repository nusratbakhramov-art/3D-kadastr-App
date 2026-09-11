import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/models/service_item.dart';
import 'package:kadastr/features/services/widgets/service_card.dart';

/// Xizmat kartasida Material RIPPLE'i bo'lmasligi kerak — qaror 2026-09-11.
///
/// Bosilgani uchta signal bilan bildiriladi (karta kichrayadi, logo sakraydi,
/// haptika), ripple to'rtinchisi bo'lardi va `highlightColor` qorong'i karta
/// ustiga oqish parda tashlab rangli glow'ni yuvib yuborardi.
void main() {
  const item = ServiceItem(
    id: ServiceId.bozorAi,
    title: 'Bozor AI',
    subtitle: 'Sun\'iy intellekt bilan bozor narxlarini tahlil qilish.',
    asset: 'assets/images/services/bozor-ai.png',
    accent: Color(0xFFF59E0B),
    layout: ServiceLayout.square,
  );

  Future<void> pumpCard(WidgetTester tester, {VoidCallback? onTap}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 220,
              child: ServiceCard(item: item, onTap: onTap ?? () {}),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('bosilganda siyoh (splash/highlight) CHIZILMAYDI', (
    tester,
  ) async {
    await pumpCard(tester);

    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.splashFactory, same(NoSplash.splashFactory));
    expect(ink.highlightColor, Colors.transparent);

    // Barmoqni kartada USHLAB turamiz — aynan shu paytda parda ko'rinardi.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ServiceCard)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    // Material siyoh chizmagan bo'lsa hech qanday `InkFeature` qatlami
    // qo'shilmaydi va kadr muammosiz chiziladi.
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('bosish baribir ishlaydi (onTap chaqiriladi)', (tester) async {
    var taps = 0;
    await pumpCard(tester, onTap: () => taps++);

    await tester.tap(find.byType(ServiceCard));
    // Logo sakrashi tugagach onTap chaqiriladi (150 ms).
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
