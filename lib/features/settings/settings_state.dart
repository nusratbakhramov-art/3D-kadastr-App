import 'package:flutter/material.dart';

/// Globally selected app locale. Defaults to Russian for now (App Store
/// review requires the app to present Russian when the device is set to it;
/// shipping Russian as the out-of-the-box default until UZ strings are fully
/// audited). A saved user preference (LocaleStorage) still overrides this.
final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(
  const Locale('ru'),
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
