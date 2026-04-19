import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/widgets/phone_input_field.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets('shows placeholder when empty', (tester) async {
    await tester.pumpWidget(wrap(PhoneInputField(onChanged: (_) {})));
    expect(find.text('+998'), findsOneWidget);
    expect(find.text('00 000-00-00'), findsOneWidget);
  });

  testWidgets('formats 9 digits as XX XXX-XX-XX', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      wrap(PhoneInputField(onChanged: (v) => emitted = v)),
    );
    await tester.enterText(find.byType(TextField), '934729335');
    await tester.pump();
    expect(emitted, '934729335');
    expect(find.text('93 472-93-35'), findsOneWidget);
  });

  testWidgets('strips non-digits and caps at 9', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      wrap(PhoneInputField(onChanged: (v) => emitted = v)),
    );
    await tester.enterText(find.byType(TextField), 'abc93-4729335xxx');
    await tester.pump();
    expect(emitted, '934729335');
  });

  testWidgets('isValidLength reflects 9 digits', (tester) async {
    final state = PhoneInputController();
    await tester.pumpWidget(
      wrap(PhoneInputField(controller: state, onChanged: (_) {})),
    );
    expect(state.isValid, isFalse);
    await tester.enterText(find.byType(TextField), '93472933');
    await tester.pump();
    expect(state.isValid, isFalse);
    await tester.enterText(find.byType(TextField), '934729335');
    await tester.pump();
    expect(state.isValid, isTrue);
  });
}
