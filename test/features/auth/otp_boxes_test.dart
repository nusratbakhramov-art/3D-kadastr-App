import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/widgets/otp_boxes.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets('renders 5 boxes', (tester) async {
    await tester.pumpWidget(wrap(OtpBoxes(length: 5, onChanged: (_) {})));
    expect(find.byKey(const ValueKey('otp.box.0')), findsOneWidget);
    expect(find.byKey(const ValueKey('otp.box.4')), findsOneWidget);
  });

  testWidgets('entering digits fills and emits', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      wrap(OtpBoxes(length: 5, onChanged: (v) => emitted = v)),
    );
    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    expect(emitted, '12345');
    expect(find.text('1'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('controller clears and sets values', (tester) async {
    final controller = OtpController(length: 5);
    await tester.pumpWidget(
      wrap(OtpBoxes(length: 5, controller: controller, onChanged: (_) {})),
    );
    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    expect(controller.value, '12345');
    controller.clear();
    await tester.pump();
    expect(controller.value, '');
  });
}
