import 'package:flutter/material.dart';

/// Globally selected app locale. Initial value matches the legacy default of
/// Uzbek so existing screens that don't read this notifier continue to work.
final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(
  const Locale('uz'),
);

/// Globally selected theme mode (system / light / dark).
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
  ThemeMode.system,
);

/// Push notifications opt-in.
final ValueNotifier<bool> notificationsEnabledNotifier = ValueNotifier<bool>(
  true,
);

/// Biometric login opt-in.
final ValueNotifier<bool> biometricEnabledNotifier = ValueNotifier<bool>(false);
