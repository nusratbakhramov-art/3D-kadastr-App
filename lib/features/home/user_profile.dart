import 'package:flutter/foundation.dart';

import '../auth/models/user_profile.dart' show Gender;

export '../auth/models/user_profile.dart' show Gender;

@immutable
class UserProfile {
  const UserProfile({
    required this.name,
    this.phone,
    this.avatarPath,
    this.dateOfBirth,
    this.gender,
  });

  final String name;
  final String? phone;

  /// Path to the avatar image. Either an asset path (e.g.
  /// `assets/images/auth/user.png`) or a filesystem path produced by
  /// image_picker. The renderer chooses [Image.asset] vs [Image.file] based on
  /// whether the path begins with `assets/`.
  final String? avatarPath;
  final DateTime? dateOfBirth;
  final Gender? gender;

  UserProfile copyWith({
    String? name,
    String? phone,
    String? avatarPath,
    DateTime? dateOfBirth,
    Gender? gender,
  }) {
    return UserProfile(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarPath: avatarPath ?? this.avatarPath,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          other.name == name &&
          other.phone == phone &&
          other.avatarPath == avatarPath &&
          other.dateOfBirth == dateOfBirth &&
          other.gender == gender;

  @override
  int get hashCode => Object.hash(name, phone, avatarPath, dateOfBirth, gender);
}

final ValueNotifier<UserProfile?> userProfileNotifier =
    ValueNotifier<UserProfile?>(null);

/// App Store reviewer / demo akkaunti telefoni. Bu foydalanuvchi uchun barcha
/// to'lov oqimlari (Profil "To'lovlar", Sozlamalar "To'lovlarim", AI ariza
/// to'lovi, Market "Sotib olish") YASHIRILADI. Backend ham shu telefonni
/// `Settings.DEMO_PHONE` sifatida biladi va `/payments/initiate` ni rad etadi —
/// ikkalasini sinxron saqlang.
const String kReviewerPhone = '+998990000011';

/// Joriy (kirgan) foydalanuvchi uchun to'lov oqimlari yashirilishi kerakmi.
/// Telefon sessiyada barqaror, shuning uchun build paytida o'qish xavfsiz.
bool get paymentsHidden => userProfileNotifier.value?.phone == kReviewerPhone;

final ValueNotifier<int> notificationUnreadNotifier = ValueNotifier<int>(0);
