import 'package:shared_preferences/shared_preferences.dart';

import 'models/auth_session.dart';
import 'models/user_profile.dart';

class AuthStorage {
  const AuthStorage();

  static const String _tokenKey = 'auth_token_v1';
  static const String _phoneKey = 'auth_phone_v1';
  static const String _nameKey = 'auth_profile_name_v1';
  static const String _dobKey = 'auth_profile_dob_v1';
  static const String _genderKey = 'auth_profile_gender_v1';

  Future<AuthSession> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final phone = prefs.getString(_phoneKey);
    if (token == null && phone == null) return const AuthSession.guest();
    return AuthSession(token: token, phone: phone);
  }

  Future<void> saveSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    if (session.token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, session.token!);
    }
    if (session.phone == null) {
      await prefs.remove(_phoneKey);
    } else {
      await prefs.setString(_phoneKey, session.phone!);
    }
  }

  Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_nameKey);
    final dobIso = prefs.getString(_dobKey);
    final genderRaw = prefs.getString(_genderKey);
    if (name == null && dobIso == null && genderRaw == null) {
      return UserProfile.empty;
    }
    return UserProfile(
      fullName: name ?? '',
      dateOfBirth: dobIso == null ? null : DateTime.tryParse(dobIso),
      gender: Gender.fromStorage(genderRaw),
    );
  }

  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, profile.fullName);
    if (profile.dateOfBirth == null) {
      await prefs.remove(_dobKey);
    } else {
      await prefs.setString(_dobKey, profile.dateOfBirth!.toIso8601String());
    }
    if (profile.gender == null) {
      await prefs.remove(_genderKey);
    } else {
      await prefs.setString(_genderKey, profile.gender!.storageValue);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_tokenKey),
      prefs.remove(_phoneKey),
      prefs.remove(_nameKey),
      prefs.remove(_dobKey),
      prefs.remove(_genderKey),
    ]);
  }
}
