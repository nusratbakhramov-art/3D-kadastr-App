import 'package:flutter/foundation.dart';

@immutable
class AuthSession {
  const AuthSession({required this.token, required this.phone});

  const AuthSession.guest() : token = null, phone = null;

  final String? token;
  final String? phone;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  AuthSession copyWith({
    String? token,
    String? phone,
    bool clearToken = false,
  }) {
    return AuthSession(
      token: clearToken ? null : (token ?? this.token),
      phone: phone ?? this.phone,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthSession && other.token == token && other.phone == phone;

  @override
  int get hashCode => Object.hash(token, phone);
}
