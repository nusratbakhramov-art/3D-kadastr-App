import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/widgets/otp_boxes.dart';
import 'package:kadastr/features/auth/widgets/resend_timer.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/screens/bozor_contacts_step_screen.dart';
import 'package:kadastr/features/bozor/widgets/bozor_phone_field.dart';
import 'package:kadastr/features/services/widgets/wizard_nav_bar.dart';
import 'param_schema_fixture.dart';

/// 6-qadamda SMS TASDIQLASH YO'Q — mahsulot qarori (2026-09-11).
///
/// Blok ishlamaydigan UI edi (tugma hech qanday so'rov yubormasdi) va
/// olib tashlandi. Bu test uni qaytarib qo'yishga to'sqinlik qiladi: kod
/// kataklari yoki "qayta yuborish" taymeri paydo bo'lsa test yiqiladi.
///
/// Yorliqlar bu yerda kalitning O'ZI bo'lib chiqadi (`bozor.contacts.name`):
/// `tr()` bundle yuklanmagan holatda kalitni qaytaradi.
void main() {
  // Sxema backenddan keladi — testda uni qo'lda yuklaymiz.
  setUpAll(loadRealParamSchema);

  BozorDraft draftAt(PropertyType type) =>
      BozorDraft(deal: DealType.rent, kind: type.kind, type: type);

  Future<void> pumpContacts(WidgetTester tester, BozorDraft draft) async {
    await tester.pumpWidget(
      MaterialApp(home: BozorContactsStepScreen(draft: draft)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('kod kataklari va qayta yuborish taymeri YO\'Q', (tester) async {
    await pumpContacts(tester, draftAt(PropertyType.apartment));

    expect(find.byType(OtpBoxes), findsNothing);
    expect(find.byType(ResendTimer), findsNothing);
    // «Yuborish» tugmasining yorlig'i ham qolmasin.
    expect(find.text('bozor.contacts.send'), findsNothing);
  });

  testWidgets('maydonlar joyida: ism, telefon, pochta', (tester) async {
    await pumpContacts(tester, draftAt(PropertyType.apartment));

    expect(find.text('bozor.contacts.name'), findsOneWidget);
    expect(find.byType(BozorPhoneField), findsOneWidget);
    expect(find.text('bozor.contacts.email'), findsOneWidget);
  });

  testWidgets(
    '«Keyingisi» ism + 9 raqamli telefonda yonadi (tasdiqlash talab qilinmaydi)',
    (tester) async {
      final draft = draftAt(PropertyType.apartment);
      await pumpContacts(tester, draft);

      WizardNavBar nav() => tester.widget<WizardNavBar>(
        find.byType(WizardNavBar),
      );
      expect(nav().continueEnabled, isFalse);

      await tester.enterText(
        find.descendant(
          of: find.byType(BozorPhoneField),
          matching: find.byType(TextField),
        ),
        '996753211',
      );
      await tester.pump();
      // Telefon to'liq, lekin ism hali yo'q.
      expect(nav().continueEnabled, isFalse);

      // Ism maydoni — telefondan tashqaridagi birinchi matn maydoni.
      final nameField = find
          .byType(TextField)
          .evaluate()
          .firstWhere(
            (e) => find
                .ancestor(
                  of: find.byWidget(e.widget),
                  matching: find.byType(BozorPhoneField),
                )
                .evaluate()
                .isEmpty,
          );
      await tester.enterText(find.byWidget(nameField.widget), 'Asliddin');
      await tester.pump();

      expect(nav().continueEnabled, isTrue);
      expect(draft.contacts.name, 'Asliddin');
      expect(draft.contacts.phones.first, '996753211');
    },
  );
}
