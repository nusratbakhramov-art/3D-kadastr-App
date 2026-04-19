import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/widgets/resend_timer.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets('shows countdown and becomes tappable when 0', (tester) async {
    var resent = 0;
    await tester.pumpWidget(
      wrap(
        ResendTimer(
          duration: const Duration(seconds: 3),
          onResend: () => resent++,
        ),
      ),
    );
    expect(find.text('00:03'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:02'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    // Now should show refresh button.
    expect(find.byKey(const ValueKey('resend.button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resend.button')));
    expect(resent, 1);
    // After tap, timer restarts.
    await tester.pump();
    expect(find.text('00:03'), findsOneWidget);
  });

  testWidgets('formats over 1 minute correctly', (tester) async {
    await tester.pumpWidget(
      wrap(ResendTimer(duration: const Duration(seconds: 90), onResend: () {})),
    );
    expect(find.text('01:30'), findsOneWidget);
  });
}
