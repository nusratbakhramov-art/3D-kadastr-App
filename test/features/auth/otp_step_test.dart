import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/auth_service.dart';
import 'package:kadastr/features/auth/screens/otp_step.dart';

Widget _host(OtpStep step) => MaterialApp(home: step);

void main() {
  testWidgets('wrong code shows error toast', (tester) async {
    final service = FakeAuthService(delay: Duration.zero);
    await service.sendOtp('998934729335');
    await tester.pumpWidget(
      _host(
        OtpStep(
          phone: '998934729335',
          service: service,
          onVerified: (_) {},
          onEdit: () {},
          onSkip: () {},
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '99999');
    await tester.pump();
    await tester.tap(find.text('Davom etish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining("noto'g'ri"), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // unmount to cancel timers
  });

  testWidgets('right code calls onVerified', (tester) async {
    final service = FakeAuthService(delay: Duration.zero);
    await service.sendOtp('998934729335');
    VerifyResult? result;
    await tester.pumpWidget(
      _host(
        OtpStep(
          phone: '998934729335',
          service: service,
          onVerified: (r) => result = r,
          onEdit: () {},
          onSkip: () {},
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    await tester.tap(find.text('Davom etish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(result, isNotNull);
    expect(result!.isNewUser, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('edit pencil fires onEdit', (tester) async {
    final service = FakeAuthService(delay: Duration.zero);
    await service.sendOtp('998934729335');
    var edited = 0;
    await tester.pumpWidget(
      _host(
        OtpStep(
          phone: '998934729335',
          service: service,
          onVerified: (_) {},
          onEdit: () => edited++,
          onSkip: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('otp.edit')));
    expect(edited, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
