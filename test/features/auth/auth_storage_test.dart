import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/auth_storage.dart';
import 'package:kadastr/features/auth/models/auth_session.dart';
import 'package:kadastr/features/auth/models/user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthStorage', () {
    test('returns guest session + empty profile by default', () async {
      const storage = AuthStorage();
      expect(await storage.loadSession(), const AuthSession.guest());
      expect(await storage.loadProfile(), UserProfile.empty);
    });

    test('persists and loads session', () async {
      const storage = AuthStorage();
      const session = AuthSession(token: 'abc', phone: '998934729335');
      await storage.saveSession(session);
      expect(await storage.loadSession(), session);
    });

    test('persists and loads profile', () async {
      const storage = AuthStorage();
      final profile = UserProfile(
        fullName: 'Ali Vali',
        dateOfBirth: DateTime(1990, 1, 15),
        gender: Gender.female,
      );
      await storage.saveProfile(profile);
      final loaded = await storage.loadProfile();
      expect(loaded.fullName, 'Ali Vali');
      expect(loaded.dateOfBirth, DateTime(1990, 1, 15));
      expect(loaded.gender, Gender.female);
    });

    test('clear wipes session and profile', () async {
      const storage = AuthStorage();
      await storage.saveSession(
        const AuthSession(token: 't', phone: '998934729335'),
      );
      await storage.saveProfile(
        UserProfile(
          fullName: 'X',
          dateOfBirth: DateTime(2000, 1, 1),
          gender: Gender.male,
        ),
      );
      await storage.clear();
      expect(await storage.loadSession(), const AuthSession.guest());
      expect(await storage.loadProfile(), UserProfile.empty);
    });
  });
}
