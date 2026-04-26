import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  const UserProfile({required this.name, this.phone, this.avatarAsset});

  final String name;
  final String? phone;
  final String? avatarAsset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          other.name == name &&
          other.phone == phone &&
          other.avatarAsset == avatarAsset;

  @override
  int get hashCode => Object.hash(name, phone, avatarAsset);
}

final ValueNotifier<UserProfile?> userProfileNotifier =
    ValueNotifier<UserProfile?>(null);

final ValueNotifier<int> notificationUnreadNotifier = ValueNotifier<int>(0);
