import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/services/screens/ai_scan_intro_screen.dart';
import 'package:kadastr/features/services/screens/ai_start_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The dev-only scan skip on the AI Baholash intro screen. It must appear only
/// when `.env` carries `admin=true` — production ships a `.env` without it.
///
/// The skip now lands on the video step ([AiStartScreen]) exactly like a device
/// without LiDAR does: that step is mandatory and owns the draft, so there is
/// no longer a path into the wizard that bypasses it.
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Skan qo'llab-quvvatlanadi deb ko'rsatamiz — aks holda ekran o'zini
    // darhol video qadamiga almashtiradi va DEV tugmasi umuman chizilmaydi.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'isSupported' ? true : null,
    );
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  tearDown(() {
    dotenv.clean();
    appTranslationsNotifier.value = AppTranslations.empty;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  String skipLabel() =>
      tr(const Locale('uz'), 'services.ai.scan_intro.skip_scan_dev');

  testWidgets('admin=true shows the skip and it opens the video step',
      (tester) async {
    dotenv.loadFromString(envString: 'admin=true');

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final skip = find.text(skipLabel());
    expect(skip, findsOneWidget);

    await tester.tap(skip);
    await tester.pumpAndSettle();

    expect(find.byType(AiStartScreen), findsOneWidget);
  });

  testWidgets('no admin key hides the skip', (tester) async {
    dotenv.loadFromString(envString: '', isOptional: true);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text(skipLabel()), findsNothing);
  });

  testWidgets('admin=false hides the skip', (tester) async {
    dotenv.loadFromString(envString: 'admin=false');

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text(skipLabel()), findsNothing);
  });
}
