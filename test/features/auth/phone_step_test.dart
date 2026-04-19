import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/screens/phone_step.dart';

void main() {
  testWidgets('CTA disabled until 9 digits; then fires onSubmit', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneStep(onSubmit: (p) => submitted = p, onSkip: () {}),
      ),
    );
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.pump();
    await tester.tap(find.text('Davom etish'));
    expect(submitted, isNull);
    await tester.enterText(find.byType(TextField), '934729335');
    await tester.pump();
    await tester.tap(find.text('Davom etish'));
    expect(submitted, '998934729335');
  });
}
