/// Yangilanish darvozasi UI — bloklovchi ekran va bekor qilinadigan oyna.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/app_update/app_release.dart';
import 'package:kadastr/core/app_update/app_update_gate.dart';
import 'package:kadastr/core/app_update/app_update_store.dart';
import 'package:kadastr/core/app_version.dart';
import 'package:kadastr/core/i18n/app_translations.dart';

/// Hech qachon `kAppVersion` ga teng bo'lmaydigan versiya.
const String _futureVersion = '99.0.0';

const _child = Scaffold(body: Center(child: Text('ILOVA MAZMUNI')));

Widget _app() => MaterialApp(
  locale: const Locale('uz'),
  home: const AppUpdateGate(locale: Locale('uz'), child: _child),
);

void main() {
  setUp(() {
    AppUpdateStore.instance.resetForTest();
    // Testlarning ko'pchiligi "ilova ochilgan" holatni tekshiradi.
    appShellReadyNotifier.value = true;
    // Tarjimalar bundle'i — tugma matnlari shundan keladi.
    appTranslationsNotifier.value = const AppTranslations(
      version: 1,
      byLang: {
        'uz': {
          'update.action_update': 'Yangilash',
          'update.action_later': 'Keyinroq',
          'update.required_title': 'Yangilanish talab qilinadi',
          'update.required_body': 'Yangi versiyani o\'rnating.',
          'update.optional_title': 'Yangi versiya mavjud',
          'update.optional_body': 'Yangilashni tavsiya qilamiz.',
          'update.open_failed': 'Do\'konni ochib bo\'lmadi.',
          'update.version_label': 'Versiya',
        },
      },
    );
  });

  tearDown(() {
    AppUpdateStore.instance.resetForTest();
    appShellReadyNotifier.value = false;
  });

  // Splash/onboarding ustida yangilanish oynasi CHIQMASLIGI kerak.
  testWidgets('nothing is shown while the app is still on splash',
      (tester) async {
    appShellReadyNotifier.value = false;
    await tester.pumpWidget(_app());
    appReleaseNotifier.value = const AppRelease(
      hasUpdate: true,
      version: '1.0.7',
      title: 'Yangilanish chiqdi',
    );
    await tester.pumpAndSettle();
    expect(find.text('Yangilanish chiqdi'), findsNothing);
    expect(find.text('Keyinroq'), findsNothing);

    // Splash tugadi — endi chiqadi.
    appShellReadyNotifier.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Yangilanish chiqdi'), findsOneWidget);
  });

  testWidgets('a required update also waits for the splash to finish',
      (tester) async {
    appShellReadyNotifier.value = false;
    await tester.pumpWidget(_app());
    appReleaseNotifier.value = const AppRelease(
      hasUpdate: true,
      required: true,
      title: 'Yangilanish shart',
    );
    await tester.pumpAndSettle();
    // Ilova mazmuni hali ko'rinadi (splash o'rnida), bloklovchi ekran emas.
    expect(find.text('ILOVA MAZMUNI'), findsOneWidget);

    appShellReadyNotifier.value = true;
    await tester.pumpAndSettle();
    expect(find.text('ILOVA MAZMUNI'), findsNothing);
    expect(find.text('Yangilanish shart'), findsOneWidget);
  });

  testWidgets('nothing is shown when there is no update', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('ILOVA MAZMUNI'), findsOneWidget);
    expect(find.text('Yangilash'), findsNothing);
  });

  testWidgets('required update replaces the whole app with a blocking screen',
      (tester) async {
    await tester.pumpWidget(_app());
    // Ataylab ilovaning O'Z versiyasidan uzoq: bu test "SIZDA x -> YANGI y"
    // qatorining IKKALA tomonini ham tekshiradi, shuning uchun ular bir xil
    // matn bo'lib qolmasligi kerak. Avval bu yerda '1.0.6' turardi va
    // `kAppVersion` 1.0.5 dan 1.0.6 ga ko'tarilgan kuni test sindi:
    // `find.text('1.0.6')` ikkita widget topdi.
    appReleaseNotifier.value = const AppRelease(
      hasUpdate: true,
      required: true,
      version: _futureVersion,
      title: 'Yangilanish shart',
      subtitle: 'Eski versiya qo\'llab-quvvatlanmaydi',
    );
    await tester.pumpAndSettle();

    // Ilova mazmuni YO'Q — foydalanuvchi davom eta olmaydi.
    expect(find.text('ILOVA MAZMUNI'), findsNothing);
    expect(find.text('Yangilanish shart'), findsOneWidget);
    expect(find.text('Yangilash'), findsOneWidget);
    // "Keyinroq" YO'Q — chiqib ketish yo'li yo'q.
    expect(find.text('Keyinroq'), findsNothing);
    // Versiya endi chip sifatida ko'rsatiladi: joriy → yangi.
    expect(find.text(_futureVersion), findsOneWidget);
    expect(find.text(kAppVersion), findsOneWidget);
  });

  testWidgets('the blocking screen cannot be popped', (tester) async {
    await tester.pumpWidget(_app());
    appReleaseNotifier.value = const AppRelease(hasUpdate: true, required: true);
    await tester.pumpAndSettle();

    final popScope = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(popScope.canPop, isFalse);
  });

  testWidgets('blocking screen falls back to bundled copy when texts are empty',
      (tester) async {
    await tester.pumpWidget(_app());
    appReleaseNotifier.value = const AppRelease(hasUpdate: true, required: true);
    await tester.pumpAndSettle();
    expect(find.text('Yangilanish talab qilinadi'), findsOneWidget);
  });

  testWidgets('optional update shows a dismissible sheet over the app',
      (tester) async {
    await tester.pumpWidget(_app());
    appReleaseNotifier.value = const AppRelease(
      hasUpdate: true,
      required: false,
      version: '1.0.6',
      buildNumber: 55,
      platform: 'ios',
      title: 'Yangi versiya',
      subtitle: 'Tezroq ishlaydi',
      description: 'Xatolar tuzatildi',
    );
    await tester.pumpAndSettle();

    // Ilova ORQADA turaveradi — bu bloklash emas.
    expect(find.text('ILOVA MAZMUNI'), findsOneWidget);
    expect(find.text('Yangi versiya'), findsOneWidget);
    expect(find.text('Xatolar tuzatildi'), findsOneWidget);
    expect(find.text('Yangilash'), findsOneWidget);
    expect(find.text('Keyinroq'), findsOneWidget);

    await tester.tap(find.text('Keyinroq'));
    await tester.pumpAndSettle();
    expect(find.text('Yangi versiya'), findsNothing);
    expect(find.text('ILOVA MAZMUNI'), findsOneWidget);
    // "Keyinroq" shu sessiya uchun eslab qolinadi.
    expect(AppUpdateStore.instance.dismissedKey, 'ios:1.0.6+55');
  });

  testWidgets('a dismissed release is not offered again in the same session',
      (tester) async {
    await tester.pumpWidget(_app());
    const release = AppRelease(
      hasUpdate: true,
      version: '1.0.6',
      buildNumber: 55,
      platform: 'ios',
      title: 'Yangi versiya',
    );
    appReleaseNotifier.value = release;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keyinroq'));
    await tester.pumpAndSettle();

    // Fondan qaytish → store xuddi shu relizni qayta e'lon qiladi.
    appReleaseNotifier.value = AppRelease.none;
    await tester.pumpAndSettle();
    appReleaseNotifier.value = release;
    await tester.pumpAndSettle();
    expect(find.text('Yangi versiya'), findsNothing);
  });

  testWidgets('an optional update that turns required starts blocking',
      (tester) async {
    await tester.pumpWidget(_app());
    appReleaseNotifier.value = const AppRelease(
      hasUpdate: true,
      title: 'Yangi versiya',
    );
    await tester.pumpAndSettle();
    expect(find.text('Keyinroq'), findsOneWidget);

    appReleaseNotifier.value = const AppRelease(
      hasUpdate: true,
      required: true,
      title: 'Yangi versiya',
    );
    await tester.pumpAndSettle();
    expect(find.text('ILOVA MAZMUNI'), findsNothing);
    expect(find.text('Keyinroq'), findsNothing);
  });
}
