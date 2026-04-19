import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/models/auth_session.dart';
import 'package:kadastr/features/auth/models/user_profile.dart';

void main() {
  group('Gender', () {
    test('parses from/to storage value', () {
      expect(Gender.male.storageValue, 'male');
      expect(Gender.female.storageValue, 'female');
      expect(Gender.fromStorage('male'), Gender.male);
      expect(Gender.fromStorage('female'), Gender.female);
      expect(Gender.fromStorage('other'), isNull);
      expect(Gender.fromStorage(null), isNull);
    });
  });

  group('UserProfile', () {
    final profile = UserProfile(
      fullName: 'Odiljon Sanoyev',
      dateOfBirth: DateTime(1998, 5, 10),
      gender: Gender.male,
    );

    test('equality by value', () {
      final same = UserProfile(
        fullName: 'Odiljon Sanoyev',
        dateOfBirth: DateTime(1998, 5, 10),
        gender: Gender.male,
      );
      expect(profile, same);
      expect(profile.hashCode, same.hashCode);
    });

    test('copyWith replaces fields', () {
      final updated = profile.copyWith(fullName: 'Ali');
      expect(updated.fullName, 'Ali');
      expect(updated.dateOfBirth, profile.dateOfBirth);
      expect(updated.gender, Gender.male);
    });

    test('isComplete requires name, dob, gender', () {
      expect(profile.isComplete, isTrue);
      expect(profile.copyWith(fullName: '').isComplete, isFalse);
      expect(profile.copyWith(fullName: '   ').isComplete, isFalse);
      expect(UserProfile.empty.isComplete, isFalse);
    });
  });

  group('AuthSession', () {
    test('guest session', () {
      const guest = AuthSession.guest();
      expect(guest.isAuthenticated, isFalse);
      expect(guest.token, isNull);
      expect(guest.phone, isNull);
    });

    test('authenticated session', () {
      const session = AuthSession(token: 't123', phone: '998934729335');
      expect(session.isAuthenticated, isTrue);
    });

    test('copyWith', () {
      const s = AuthSession(token: 't', phone: '998934729335');
      final cleared = s.copyWith(clearToken: true);
      expect(cleared.token, isNull);
      expect(cleared.phone, '998934729335');
    });
  });
}
