import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/services/screens/ai_cadastre_screen.dart';
import 'package:kadastr/features/services/screens/ai_scan_intro_screen.dart';
import 'package:kadastr/features/services/widgets/scan_skip_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI Baholash intro ekranidan skansiz chiqish.
///
/// Ikkala yo'l ham — foydalanuvchi "o'tkazib yuborish"ni bossa ham, qurilma
/// LiDAR ni qo'llamasa ham — wizardning BIRINCHI qadamiga, kadastrga olib
/// boradi. Ilgari bu yerda video qadami turardi; u oqimdan olib tashlangan va
/// bu test uni qaytarib qo'yishga to'sqinlik qiladi.
void main() {
  const channel = MethodChannel('kadastr/room_plan_scanner');

  Widget wrap() => MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
        home: const AiScanIntroScreen(),
      );

  /// Qurilma LiDAR ni qo'llaydimi — nativ kanal shu bitta javob bilan
  /// taqlid qilinadi.
  void mockSupported({required bool supported}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'isSupported' ? supported : null,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  tearDown(() {
    appTranslationsNotifier.value = AppTranslations.empty;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('«o\'tkazib yuborish» kadastr qadamini ochadi', (tester) async {
    mockSupported(supported: true);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final skip = find.byType(ScanSkipButton);
    expect(skip, findsOneWidget);

    await tester.tap(skip);
    await tester.pumpAndSettle();

    expect(find.byType(AiCadastreScreen), findsOneWidget);
  });

  testWidgets('LiDAR yo\'q qurilma — ekran o\'zini kadastrga almashtiradi',
      (tester) async {
    mockSupported(supported: false);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(AiCadastreScreen), findsOneWidget);
    // pushReplacement — orqaga qaytadigan intro ekran qolmaydi.
    expect(find.byType(AiScanIntroScreen), findsNothing);
  });
}
