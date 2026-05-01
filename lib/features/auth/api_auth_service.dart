import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'auth_service.dart';
import 'models/user_profile.dart';

class ApiAuthService implements AuthService {
  ApiAuthService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 15);

  String _formatPhone(String phone) {
    // Mobile yuboradi: '998901234567' (12 raqam, + yo'q)
    // Backend kutadi: '+998901234567'
    return phone.startsWith('+') ? phone : '+$phone';
  }

  Map<String, String> _jsonHeaders([String? token]) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Never _throwFromResponse(http.Response res) {
    String message = 'Server bilan aloqa muammosi';
    try {
      final body = jsonDecode(res.body);
      if (body is Map) {
        final detail = body['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail is Map && detail['message'] is String) {
          message = detail['message'] as String;
        } else if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] is String) {
            message = first['msg'] as String;
          }
        }
      }
    } catch (_) {}
    throw AuthException(message);
  }

  @override
  Future<OtpTicket> sendOtp(String phone) async {
    final formatted = _formatPhone(phone);
    try {
      final res = await _client
          .post(
            Uri.parse('$_baseUrl/auth/send-otp'),
            headers: _jsonHeaders(),
            body: jsonEncode({'phone': formatted}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) _throwFromResponse(res);
      // Backend kodning o'zini qaytarmaydi (xavfsizlik). Faqat ticket joylashtirib qo'yamiz.
      return OtpTicket(phone: phone, expectedCode: '');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException("Tarmoq xatosi: $e");
    }
  }

  @override
  Future<VerifyResult> verifyOtp(String phone, String code) async {
    final formatted = _formatPhone(phone);
    try {
      final res = await _client
          .post(
            Uri.parse('$_baseUrl/auth/verify-otp'),
            headers: _jsonHeaders(),
            body: jsonEncode({
              'phone': formatted,
              'code': code,
              'device_info': 'mobile',
            }),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) _throwFromResponse(res);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return VerifyResult(
        token: body['access_token'] as String,
        isNewUser: (body['is_new_user'] as bool?) ?? false,
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException("Tarmoq xatosi: $e");
    }
  }

  @override
  Future<UserProfile> fetchProfile(String token) async {
    try {
      final res = await _client
          .get(
            Uri.parse('$_baseUrl/profile/'),
            headers: _jsonHeaders(token),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) _throwFromResponse(res);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final fullName = (body['full_name'] as String?) ?? '';
      final dobStr = body['date_of_birth'] as String?;
      final genderStr = body['gender'] as String?;
      return UserProfile(
        fullName: fullName,
        dateOfBirth: dobStr == null ? null : DateTime.tryParse(dobStr),
        gender: Gender.fromStorage(genderStr),
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException("Tarmoq xatosi: $e");
    }
  }

  @override
  Future<void> completeProfile(String token, UserProfile profile) async {
    if (!profile.isComplete) {
      throw const AuthException("Profil to'liq emas");
    }
    try {
      final res = await _client
          .put(
            Uri.parse('$_baseUrl/profile/'),
            headers: _jsonHeaders(token),
            body: jsonEncode({
              'full_name': profile.fullName,
              'date_of_birth': profile.dateOfBirth!
                  .toIso8601String()
                  .substring(0, 10),
              'gender': profile.gender!.storageValue,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) _throwFromResponse(res);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException("Tarmoq xatosi: $e");
    }
  }
}
