import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/services/screens/ai_area_screen.dart';
import 'package:kadastr/features/services/screens/ai_scan_intro_screen.dart';

/// The dev-only scan skip on the AI Baholash intro screen. It must appear only
/// when `.env` carries `admin=true` — production ships a `.env` without it.
void main() {
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

  tearDown(dotenv.clean);

  testWidgets('admin=true shows the skip and it opens the area step',
      (tester) async {
    dotenv.loadFromString(envString: 'admin=true');

    await tester.pumpWidget(wrap());
    await tester.pump();

    final skip = find.text('Skanni o\'tkazib yuborish (DEV)');
    expect(skip, findsOneWidget);

    await tester.tap(skip);
    await tester.pumpAndSettle();

    expect(find.byType(AiAreaScreen), findsOneWidget);
  });

  testWidgets('no admin key hides the skip', (tester) async {
    dotenv.loadFromString(envString: '', isOptional: true);

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Skanni o\'tkazib yuborish (DEV)'), findsNothing);
  });

  testWidgets('admin=false hides the skip', (tester) async {
    dotenv.loadFromString(envString: 'admin=false');

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Skanni o\'tkazib yuborish (DEV)'), findsNothing);
  });
}
