import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  const UserProfile({required this.name, this.avatarAsset});

  final String name;
  final String? avatarAsset;
}

final ValueNotifier<UserProfile?> userProfileNotifier =
    ValueNotifier<UserProfile?>(null);

final ValueNotifier<int> notificationUnreadNotifier = ValueNotifier<int>(0);
