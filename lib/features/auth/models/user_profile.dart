import 'package:flutter/foundation.dart';

enum Gender {
  male('male'),
  female('female');

  const Gender(this.storageValue);

  final String storageValue;

  static Gender? fromStorage(String? value) {
    for (final g in Gender.values) {
      if (g.storageValue == value) return g;
    }
    return null;
  }
}

@immutable
class UserProfile {
  const UserProfile({
    required this.fullName,
    required this.dateOfBirth,
    required this.gender,
  });

  static const UserProfile empty = UserProfile._empty();

  const UserProfile._empty() : fullName = '', dateOfBirth = null, gender = null;

  final String fullName;
  final DateTime? dateOfBirth;
  final Gender? gender;

  bool get isComplete =>
      fullName.trim().isNotEmpty && dateOfBirth != null && gender != null;

  UserProfile copyWith({
    String? fullName,
    DateTime? dateOfBirth,
    Gender? gender,
  }) {
    return UserProfile(
      fullName: fullName ?? this.fullName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          other.fullName == fullName &&
          other.dateOfBirth == dateOfBirth &&
          other.gender == gender;

  @override
  int get hashCode => Object.hash(fullName, dateOfBirth, gender);
}
