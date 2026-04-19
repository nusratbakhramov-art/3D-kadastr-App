import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/auth_service.dart';

void main() {
  group('FakeAuthService', () {
    test('sendOtp returns an OtpTicket for valid phone', () async {
      final service = FakeAuthService(delay: Duration.zero);
      final ticket = await service.sendOtp('998934729335');
      expect(ticket.phone, '998934729335');
      expect(ticket.expectedCode, '12345');
    });

    test('sendOtp rejects short phone', () async {
      final service = FakeAuthService(delay: Duration.zero);
      expect(() => service.sendOtp('12345'), throwsA(isA<AuthException>()));
    });

    test('verifyOtp returns token when code matches', () async {
      final service = FakeAuthService(delay: Duration.zero);
      await service.sendOtp('998934729335');
      final result = await service.verifyOtp('998934729335', '12345');
      expect(result.token, isNotEmpty);
      expect(result.isNewUser, isTrue);
    });

    test('verifyOtp throws on wrong code', () async {
      final service = FakeAuthService(delay: Duration.zero);
      await service.sendOtp('998934729335');
      expect(
        () => service.verifyOtp('998934729335', '99999'),
        throwsA(isA<AuthException>()),
      );
    });

    test('verifyOtp marks existing user as not new', () async {
      final service = FakeAuthService(
        delay: Duration.zero,
        existingPhones: {'998900000000'},
      );
      await service.sendOtp('998900000000');
      final result = await service.verifyOtp('998900000000', '12345');
      expect(result.isNewUser, isFalse);
    });
  });
}
