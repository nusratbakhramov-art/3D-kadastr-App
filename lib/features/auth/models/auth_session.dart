import 'package:flutter/foundation.dart';

@immutable
class AuthSession {
  const AuthSession({
    required this.token,
    required this.phone,
    this.refreshToken,
  });

  const AuthSession.guest()
      : token = null,
        phone = null,
        refreshToken = null;

  /// Joriy access token (24 soat amal qiladi).
  final String? token;
  final String? phone;

  /// Refresh token (30 kun) — access token muddati o'tganda yangi access olish
  /// uchun ishlatiladi. `auth_interceptor.dart`'dagi 401 handler chaqiradi.
  final String? refreshToken;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  AuthSession copyWith({
    String? token,
    String? phone,
    String? refreshToken,
    bool clearToken = false,
  }) {
    return AuthSession(
      token: clearToken ? null : (token ?? this.token),
      phone: phone ?? this.phone,
      refreshToken: clearToken ? null : (refreshToken ?? this.refreshToken),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthSession &&
          other.token == token &&
          other.phone == phone &&
          other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(token, phone, refreshToken);
}
