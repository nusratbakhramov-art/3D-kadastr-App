import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/services/models/ai_baholash_bundle.dart';
import 'package:kadastr/features/services/widgets/room_picker_sheet.dart';

/// Xona tanlash varag'i. Sakkizta qat'iy tur har qanday xonadonni qoplamaydi
/// (ish xonasi, ayvon, garaj...), shuning uchun "Boshqa" tanlanganda varaq
/// yopilmaydi — nom so'raladi. Nomsiz bir nechta "Boshqa" ro'yxatda
/// bir-biridan farq qilmasdi.
void main() {
  const uz = Locale('uz');

  String label(String key) => tr(uz, key);

  setUp(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  tearDown(() => appTranslationsNotifier.value = AppTranslations.empty);

  /// Varaq yopilgach natija shu yerga tushadi; `closed` — varaq umuman
  /// yopilganini bildiradi (null tanlov ham natija).
  late RoomChoice? picked;
  late bool closed;

  Future<void> open(WidgetTester tester) async {
    picked = null;
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: uz,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showRoomPickerSheet(context);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Ro'yxat suriladi — "Boshqa" oxirgi kafel va sinov ekranida (800x600)
  /// ko'rinish maydonidan pastda qoladi.
  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('oddiy xona bir teginishda tanlanadi', (tester) async {
    await open(tester);

    await tapText(tester, label('services.model.room.kitchen'));

    expect(closed, isTrue);
    expect(picked?.kind, RoomKind.kitchen);
    expect(picked?.name, isNull);
  });

  testWidgets('"Boshqa" varaqni yopmaydi — nom maydoni ochiladi',
      (tester) async {
    await open(tester);

    expect(find.byType(TextField), findsNothing);

    await tapText(tester, label('services.model.room.other'));

    expect(closed, isFalse, reason: 'avval nom so\'ralishi kerak');
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.text(label('services.ai.capture.room_name_label')),
      findsOneWidget,
    );

    // Nomsiz "Boshqa" ning ma'nosi yo'q — tasdiqlash tugmasi ishlamaydi.
    await tapText(tester, label('services.ai.capture.continue'));
    expect(closed, isFalse);
  });

  testWidgets('kiritilgan nom tanlov bilan qaytadi', (tester) async {
    await open(tester);

    await tapText(tester, label('services.model.room.other'));
    await tester.enterText(find.byType(TextField), '  Ish xonasi  ');
    await tester.pumpAndSettle();
    await tapText(tester, label('services.ai.capture.continue'));

    expect(closed, isTrue);
    expect(picked?.kind, RoomKind.other);
    expect(picked?.name, 'Ish xonasi', reason: 'bo\'shliqlar kesiladi');
    expect(picked?.label(uz), 'Ish xonasi');
  });
}
