import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/models/user_profile.dart';
import 'package:kadastr/features/auth/widgets/auth_toast.dart';
import 'package:kadastr/features/auth/widgets/dob_field.dart';
import 'package:kadastr/features/auth/widgets/gender_toggle.dart';
import 'package:kadastr/features/auth/widgets/primary_cta.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets('GenderToggle selects and emits', (tester) async {
    Gender? chosen;
    await tester.pumpWidget(
      wrap(GenderToggle(value: Gender.male, onChanged: (g) => chosen = g)),
    );
    await tester.tap(find.text('Ayol'));
    expect(chosen, Gender.female);
  });

  testWidgets('DobField opens picker and shows formatted date', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      wrap(
        DobField(value: DateTime(1998, 5, 10), onChanged: (d) => picked = d),
      ),
    );
    expect(find.text('10.05.1998'), findsOneWidget);
    expect(picked, isNull);
  });

  testWidgets('AuthToast renders text', (tester) async {
    await tester.pumpWidget(
      wrap(const AuthToast(message: 'Hello', variant: AuthToastVariant.error)),
    );
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('PrimaryCta disabled state blocks onPressed', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(
        PrimaryCta(
          label: 'Davom etish',
          enabled: false,
          onPressed: () => tapped++,
        ),
      ),
    );
    await tester.tap(find.byType(PrimaryCta));
    expect(tapped, 0);
  });

  testWidgets('PrimaryCta enabled triggers callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(
        PrimaryCta(
          label: 'Davom etish',
          enabled: true,
          onPressed: () => tapped++,
        ),
      ),
    );
    await tester.tap(find.byType(PrimaryCta));
    expect(tapped, 1);
  });
}
