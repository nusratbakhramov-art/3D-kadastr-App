import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/models/user_profile.dart';
import 'package:kadastr/features/auth/screens/profile_step.dart';

void main() {
  testWidgets('submit blocked when fields missing', (tester) async {
    UserProfile? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileStep(
          onSubmit: (p) => submitted = p,
          onSkip: () {},
          onBack: () {},
        ),
      ),
    );
    await tester.tap(find.text('Kirish'));
    await tester.pump();
    expect(submitted, isNull);
  });

  testWidgets('submit works when all fields valid', (tester) async {
    UserProfile? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileStep(
          initial: UserProfile(
            fullName: 'Odiljon Sanoyev',
            dateOfBirth: DateTime(1998, 5, 10),
            gender: Gender.male,
          ),
          onSubmit: (p) => submitted = p,
          onSkip: () {},
          onBack: () {},
        ),
      ),
    );
    await tester.tap(find.text('Kirish'));
    await tester.pump();
    expect(submitted, isNotNull);
    expect(submitted!.fullName, 'Odiljon Sanoyev');
    expect(submitted!.gender, Gender.male);
  });
}
