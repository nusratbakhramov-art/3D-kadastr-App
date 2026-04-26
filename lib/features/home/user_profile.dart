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

final ValueNotifier<int> notificationUnreadNotifier = ValueNotifier<int>(0);
