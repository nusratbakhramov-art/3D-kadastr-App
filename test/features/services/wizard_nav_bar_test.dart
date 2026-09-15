import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/market/widgets/listing_cta_button.dart';
import 'package:kadastr/features/services/widgets/wizard_nav_bar.dart';

/// AI Baholash qadamlarining pastki navigatsiyasi va butun oqimni yopish.
///
/// Ikki qoida qulflanadi:
/// * yolg'iz qolgan tugma butun kenglikni egallaydi (birinchi qadamda ortga
///   yo'q, oxirgi qadamda davom etish yo'q);
/// * yuqoridagi tugma bitta qadam emas, BUTUN oqimni yopadi.
void main() {
  const uz = Locale('uz');
  const width = 400.0;

  String label(String key) => tr(uz, key);

  setUp(() {
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(File('assets/i18n/bundle.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  tearDown(() => appTranslationsNotifier.value = AppTranslations.empty);

  Widget wrap(Widget child) => MaterialApp(
        locale: uz,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  String backText() => label('services.ai.common.back');
  String backShortText() => label('services.ai.common.back_short');
  String continueText() => label('services.ai.common.continue');

  /// [tr] kalit topilmasa XOM KALITNI qaytaradi (`app_translations.dart` da
  /// ataylab shunday), ya'ni seed'ga qo'shilmagan matn ekranda
  /// "services.ai.common.back_short" bo'lib chiqadi. Shuning uchun bu panel
  /// ishlatadigan har bir kalit seed'da BOR ekanini alohida tekshiramiz —
  /// aks holda buni faqat qurilmada ko'rar edik.
  test('panel kalitlari seed bundle\'ida bor', () {
    const expected = {
      'services.ai.common.continue': {
        'uz': 'Davom etish',
        'ru': 'Продолжить',
        'en': 'Continue',
      },
      'services.ai.common.back': {
        'uz': 'Ortga qaytish',
        'ru': 'Назад',
        'en': 'Back',
      },
      'services.ai.common.back_short': {
        'uz': 'Ortga',
        'ru': 'Назад',
        'en': 'Back',
      },
    };
    for (final entry in expected.entries) {
      for (final byLang in entry.value.entries) {
        expect(
          tr(Locale(byLang.key), entry.key),
          byLang.value,
          reason: '${entry.key} (${byLang.key}) seed\'da yo\'q yoki boshqacha',
        );
      }
    }
  });

  group('joylashuv', () {
    testWidgets('ikkala tugma: ortga chapda, davom etish o\'ngda',
        (tester) async {
      await tester.pumpWidget(wrap(WizardNavBar(
        onBack: () {},
        onContinue: () {},
      )));

      // Qator ekran markazida turgan `SizedBox` ichida — chegaralar undan
      // olinadi, ekran kengligidan emas.
      final row = tester.getRect(find.byType(WizardNavBar));
      // Ortga tugmasining o'zi — matnining eng yaqin `Material` ajdodi.
      final back = tester.getRect(
        find
            .ancestor(
              of: find.text(backShortText()),
              matching: find.byType(Material),
            )
            .first,
      );
      final next = tester.getRect(find.byType(ListingCtaButton));

      expect(back.center.dx, lessThan(next.center.dx),
          reason: 'ortga chapda turishi kerak');
      expect(back.width, moreOrLessEquals(next.width, epsilon: 0.5),
          reason: 'qator teng ikkiga bo\'linishi kerak');
      expect(back.left, moreOrLessEquals(row.left, epsilon: 0.5),
          reason: 'ortga chap chetdan boshlanadi');
      expect(next.right, moreOrLessEquals(row.right, epsilon: 0.5),
          reason: 'davom etish o\'ng chetgacha cho\'ziladi');
      expect(tester.takeException(), isNull,
          reason: 'qator toshib ketmasligi kerak');
    });

    testWidgets('birinchi qadam — ortga yo\'q, davom etish butun kenglikda',
        (tester) async {
      await tester.pumpWidget(wrap(WizardNavBar(onContinue: () {})));

      expect(find.text(backText()), findsNothing);
      expect(find.text(backShortText()), findsNothing);
      expect(tester.getSize(find.byType(ListingCtaButton)).width, width);
    });

    testWidgets('davom etadigan qadam yo\'q — ortga butun kenglikda',
        (tester) async {
      await tester.pumpWidget(wrap(WizardNavBar(onBack: () {})));

      expect(find.byType(ListingCtaButton), findsNothing);
      expect(find.text(backText()), findsOneWidget);
      // Matn emas, tugmaning o'zi o'lchanadi — u butun qatorni egallaydi.
      final button = find.ancestor(
        of: find.text(backText()),
        matching: find.byType(Material),
      );
      expect(tester.getSize(button.first).width, width);
    });

    /// iPhone SE kengligi (320pt) minus 16+16 padding. Ikkala to'liq nom bir
    /// qatorga sig'masdi — shuning uchun yonma-yon turganda qisqa nom.
    testWidgets('tor ekranda ham qator toshib ketmaydi', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: uz,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 288,
              child: WizardNavBar(onBack: () {}, onContinue: () {}),
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      final back = tester.getRect(find.text(backShortText()));
      final next = tester.getRect(find.byType(ListingCtaButton));
      expect(back.right, lessThan(next.left));
    });

    testWidgets('ikkalasi ham yo\'q — hech narsa chizilmaydi', (tester) async {
      await tester.pumpWidget(wrap(const WizardNavBar()));

      expect(find.text(backText()), findsNothing);
      expect(find.byType(ListingCtaButton), findsNothing);
    });
  });

  group('bosilish', () {
    testWidgets('o\'chiq davom etish onContinue ni chaqirmaydi', (tester) async {
      var continued = 0;
      var blocked = 0;
      await tester.pumpWidget(wrap(WizardNavBar(
        onBack: () {},
        onContinue: () => continued++,
        continueEnabled: false,
        onBlockedTap: () => blocked++,
      )));

      await tester.tap(find.text(continueText()));
      await tester.pumpAndSettle();

      expect(continued, 0, reason: 'to\'ldirilmagan forma o\'tkazmasligi kerak');
      expect(blocked, 1, reason: 'nimasi yetishmayotgani aytilishi kerak');
    });

    testWidgets('ortga forma to\'ldirilmagan bo\'lsa ham bosiladi',
        (tester) async {
      var back = 0;
      await tester.pumpWidget(wrap(WizardNavBar(
        onBack: () => back++,
        onContinue: () {},
        continueEnabled: false,
      )));

      await tester.tap(find.text(backShortText()));
      await tester.pumpAndSettle();

      expect(back, 1);
    });
  });

  /// Yuqoridagi doiraviy tugma bitta qadam emas, butun oqimni yopadi:
  /// `ai/` bilan boshlanadigan marshrutlarning hammasi bir yo'la poplanadi.
  testWidgets('closeAiWizard butun ai/ steklarini poplaydi', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('entry')),
    ));

    for (final name in ['ai/scan-intro', 'ai/start', 'ai/cadastre', 'ai/client']) {
      nav.currentState!.push(MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => Scaffold(body: Text(name)),
      ));
    }
    await tester.pumpAndSettle();
    expect(find.text('ai/client'), findsOneWidget);

    closeAiWizard(nav.currentContext!);
    await tester.pumpAndSettle();

    expect(find.text('entry'), findsOneWidget);
    for (final name in ['ai/scan-intro', 'ai/start', 'ai/cadastre', 'ai/client']) {
      expect(find.text(name), findsNothing, reason: '$name qolib ketdi');
    }
  });

  testWidgets('closeAiWizard oqimdan tashqaridagi ekranda to\'xtaydi',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('entry')),
    ));

    // Ariza tafsiloti — nomsiz marshrut. Draft o'sha yerdan tiklanadi,
    // shuning uchun yopish AYNAN shu ekranga qaytishi kerak, bosh sahifaga
    // emas.
    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('ariza-detail')),
    ));
    for (final name in ['ai/cadastre', 'ai/client']) {
      nav.currentState!.push(MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => Scaffold(body: Text(name)),
      ));
    }
    await tester.pumpAndSettle();

    closeAiWizard(nav.currentContext!);
    await tester.pumpAndSettle();

    expect(find.text('ariza-detail'), findsOneWidget);
    expect(find.text('entry'), findsNothing);
  });
}
