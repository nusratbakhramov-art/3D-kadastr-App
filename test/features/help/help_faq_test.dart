// Yordam sahifasidagi savollar SONI kodda emas, tarjimalar to'plamida hal
// bo'lishi kerak.
//
// Oldin `for (var i = 1; i <= 5; i++)` turardi: admin Tarjimalar sahifasida
// mavjud beshta savol matnini o'zgartira olardi, lekin oltinchisini qo'sha
// olmasdi va kamaytira ham olmasdi — har safar yangi reliz kerak edi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/help/help_screen.dart';

void useFaq(int count, {bool lastAnswerMissing = false}) {
  final uz = <String, String>{
    'help.title': 'Yordam',
    'help.faq_label': 'Savollar',
    'help.contact_label': 'Aloqa',
    'help.telegram': 'Telegram',
    'help.email': 'Pochta',
    'help.phone': 'Telefon',
  };
  for (var i = 1; i <= count; i++) {
    uz['help.faq.q$i'] = 'SAVOL $i';
    final skip = lastAnswerMissing && i == count;
    if (!skip) uz['help.faq.a$i'] = 'JAVOB $i';
  }
  appTranslationsNotifier.value = AppTranslations(version: 1, byLang: {'uz': uz});
}

Future<void> pumpHelp(WidgetTester t) async {
  await t.pumpWidget(
    const MaterialApp(locale: Locale('uz'), home: HelpScreen()),
  );
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('uchta savol bo\'lsa — uchtasi chiqadi', (t) async {
    useFaq(3);
    await pumpHelp(t);
    expect(find.text('SAVOL 1'), findsOneWidget);
    expect(find.text('SAVOL 3'), findsOneWidget);
    expect(find.text('SAVOL 4'), findsNothing);
  });

  testWidgets('oltinchi savol qo\'shilsa RELIZSIZ chiqadi', (t) async {
    useFaq(6);
    await pumpHelp(t);
    expect(find.text('SAVOL 6'), findsOneWidget);
  });

  testWidgets('savol yo\'q bo\'lsa — hech narsa chiqmaydi, xato ham yo\'q', (t) async {
    useFaq(0);
    await pumpHelp(t);
    expect(find.text('SAVOL 1'), findsNothing);
    // Sahifa baribir ochiladi — aloqa bo'limi joyida.
    expect(find.text('Aloqa'), findsOneWidget);
  });

  testWidgets('javobi yo\'q savol ham ro\'yxatda qoladi', (t) async {
    useFaq(2, lastAnswerMissing: true);
    await pumpHelp(t);
    expect(find.text('SAVOL 2'), findsOneWidget);
    // Kalitning o'zi ekranda ko'rinmasligi kerak.
    expect(find.text('help.faq.a2'), findsNothing);
  });
}
