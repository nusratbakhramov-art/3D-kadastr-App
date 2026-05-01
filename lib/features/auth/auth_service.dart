import 'models/user_profile.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}

class OtpTicket {
  const OtpTicket({required this.phone, required this.expectedCode});
  final String phone;
  final String expectedCode;
}

class VerifyResult {
  const VerifyResult({required this.token, required this.isNewUser});
  final String token;
  final bool isNewUser;
}

abstract class AuthService {
  Future<OtpTicket> sendOtp(String phone);
  Future<VerifyResult> verifyOtp(String phone, String code);
  Future<void> completeProfile(String token, UserProfile profile);
  Future<UserProfile> fetchProfile(String token);
}

class FakeAuthService implements AuthService {
  FakeAuthService({
    this.delay = const Duration(milliseconds: 400),
    Set<String>? existingPhones,
  }) : _existingPhones = existingPhones ?? const <String>{};

  static const String fixedCode = '12345';

  final Duration delay;
  final Set<String> _existingPhones;
  final Map<String, String> _pending = {};

  @override
  Future<OtpTicket> sendOtp(String phone) async {
    await Future<void>.delayed(delay);
    if (phone.length != 12 || !phone.startsWith('998')) {
      throw const AuthException('Telefon raqami noto\'g\'ri');
    }
    _pending[phone] = fixedCode;
    return OtpTicket(phone: phone, expectedCode: fixedCode);
  }

  @override
  Future<VerifyResult> verifyOtp(String phone, String code) async {
    await Future<void>.delayed(delay);
    final expected = _pending[phone];
    if (expected == null || code != expected) {
      throw const AuthException(
        'Siz kiritgan tasdiqlash kodi noto\'g\'ri kiritilgan!',
      );
    }
    _pending.remove(phone);
    final isNewUser = !_existingPhones.contains(phone);
    return VerifyResult(
      token: 'fake_token_${DateTime.now().millisecondsSinceEpoch}',
      isNewUser: isNewUser,
    );
  }

  @override
  Future<void> completeProfile(String token, UserProfile profile) async {
    await Future<void>.delayed(delay);
    if (!profile.isComplete) {
      throw const AuthException('Profil to\'liq emas');
    }
  }

  @override
  Future<UserProfile> fetchProfile(String token) async {
    await Future<void>.delayed(delay);
    return UserProfile.empty;
  }
}
