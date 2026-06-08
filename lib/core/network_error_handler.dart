import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../features/auth/auth_service.dart';
import '../widgets/no_internet_sheet.dart';

/// Routes API exceptions caused by lost connectivity to a single animated
/// "no internet" bottom sheet so individual screens don't each render their
/// own ad-hoc error toast.
///
/// Usage in a catch block:
/// ```dart
/// try {
///   await api.call();
/// } catch (e) {
///   if (await NetworkErrorHandler.maybeShow(context, e, onRetry: _retry)) {
///     return; // handled — sheet was shown
///   }
///   AppToast.error(context, '$e'); // fallback for non-network errors
/// }
/// ```
class NetworkErrorHandler {
  const NetworkErrorHandler._();

  static bool _visible = false;

  /// True if [error] looks like a connectivity / DNS / timeout failure rather
  /// than a server-side error (HTTP 4xx/5xx).
  static bool isNetworkError(Object error) {
    if (error is AuthException && error.cause != null) {
      return isNetworkError(error.cause!);
    }
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) return true;
    if (error is http.ClientException) {
      final msg = error.message.toLowerCase();
      return msg.contains('failed host lookup') ||
          msg.contains('connection closed') ||
          msg.contains('connection refused') ||
          msg.contains('connection reset') ||
          msg.contains('network is unreachable') ||
          msg.contains('software caused connection abort') ||
          msg.contains('no address associated') ||
          msg.contains('connection terminated') ||
          msg.contains('socketexception');
    }
    final s = error.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup');
  }

  /// If [error] is a network error, show the bottom sheet and return true.
  /// Otherwise return false so the caller can fall through to its normal
  /// error handling. De-dupes concurrent shows from parallel failed requests.
  static Future<bool> maybeShow(
    BuildContext context,
    Object error, {
    VoidCallback? onRetry,
  }) async {
    if (!isNetworkError(error)) return false;
    if (_visible) return true;
    if (!context.mounted) return true;
    _visible = true;
    try {
      await NoInternetSheet.show(context, onRetry: onRetry);
    } finally {
      _visible = false;
    }
    return true;
  }
}
