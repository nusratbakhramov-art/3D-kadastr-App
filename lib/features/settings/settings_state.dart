import 'package:flutter/material.dart';

/// Globally selected app locale. Defaults to **Uzbek** when the user has not
/// yet picked a language. A saved user preference (LocaleStorage) overrides
/// this on startup.
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
