/// Video qadami IXTIYORIY: 3DGS modeli baholash sifatini oshiradi, lekin usiz
/// ham ariza to'ldiriladi — shuning uchun "Hozircha o'tkazib yuborish" yo'li
/// har doim ochiq bo'lishi kerak.
///
/// Bu qadam bir marta majburiy qilingan edi va qaytarib olindi; test aynan shu
/// yo'lni qo'riqlaydi.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/market/widgets/listing_cta_button.dart';
import 'package:kadastr/features/services/screens/ai_start_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const uz = Locale('uz');

  String label(String key) => tr(uz, 'services.ai.capture.$key');

  /// Asosiy tugmaning matni. Ekran sarlavhasi ham "Videoga olish" — shuning
  /// uchun matn butun ekrandan emas, AYNAN tugmadan qidiriladi.
  Finder cta(String key) => find.descendant(
        of: find.byType(ListingCtaButton),
        matching: find.text(label(key)),
      );

  /// Ariza id hali yo'q holat — "draftsiz" yig'ilgan xonalar kaliti.
  void seedRooms(List<Map<String, dynamic>> rooms) =>
      SharedPreferences.setMockInitialValues({
        'v2m_rooms_no_ariza': jsonEncode(rooms),
      });

  Map<String, dynamic> room({String? modelId, String? status}) => {
        'room': 'living',
        'videoPath': '/tmp/living.mov',
        'createdAt': DateTime(2026, 8, 28).toIso8601String(),
        'modelId': ?modelId,
        'status': ?status,
      };

  Future<void> pumpStep(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: uz,
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('uz'), Locale('ru'), Locale('en')],
        home: AiStartScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  tearDown(() => appTranslationsNotifier.value = AppTranslations.empty);

  testWidgets('video yo\'q — o\'tkazib yuborish yo\'li ochiq', (tester) async {
    await pumpStep(tester);

    expect(cta('record'), findsOneWidget);
    expect(find.text(label('skip')), findsOneWidget);
  });

  testWidgets('video olingan, lekin yuklanmagan — o\'tkazib yuborish qoladi',
      (tester) async {
    seedRooms([room()]); // modelId yo'q = serverga chiqmagan
    await pumpStep(tester);

    expect(find.text(label('status_pending')), findsOneWidget);
    // Bitta xona olingandan keyin asosiy tugma "Yana xona qo'shish" bo'ladi,
    // o'tkazib yuborish esa ostida qolaveradi.
    expect(cta('add_room'), findsOneWidget);
    expect(find.text(label('skip')), findsOneWidget);
  });

  testWidgets('video yuklangan — asosiy tugma davom etishga aylanadi',
      (tester) async {
    // Ishlov berish holati muhim emas: model 10-20 daqiqa tayyorlanadi va
    // foydalanuvchini shuncha kutdirib bo'lmaydi.
    seedRooms([room(modelId: '0828-a1b2c3', status: 'processing')]);
    await pumpStep(tester);

    expect(cta('continue'), findsOneWidget);
    expect(find.text(label('add_room')), findsOneWidget);
    // Davom etish allaqachon asosiy tugmada — o'tkazib yuborishning ma'nosi
    // qolmaydi.
    expect(find.text(label('skip')), findsNothing);
  });
}
