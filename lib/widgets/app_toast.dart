import 'package:flutter/material.dart';

import '../features/auth/widgets/auth_toast.dart';

/// App-wide toast facade. Delegates to the overlay-based [AuthToasts]
/// implementation that already lives in the auth module.
///
/// Usage:
/// ```dart
/// AppToast.success(context, 'Profil saqlandi');
/// AppToast.error(context, e.message);
/// ```
class AppToast {
  const AppToast._();

  /// Show a green success toast at the top of the screen.
  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) => AuthToasts.show(
    context,
    message: message,
    variant: AuthToastVariant.success,
    duration: duration,
  );

  /// Show a red error toast at the top of the screen.
  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) => AuthToasts.show(
    context,
    message: message,
    variant: AuthToastVariant.error,
    duration: duration,
  );

  /// Dismiss any visible toast.
  static void dismiss() => AuthToasts.dismiss();
}
