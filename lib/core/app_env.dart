import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Local `.env` flags. The file is gitignored — production builds ship one
/// without `admin`, so every developer-only shortcut below stays off there.
class AppEnv {
  const AppEnv._();

  /// Reads `.env` into [dotenv]. `isOptional` keeps a missing or empty file
  /// from throwing — every flag then falls back to its default (off), which is
  /// the production behaviour anyway.
  static Future<void> load() => dotenv.load(isOptional: true);

  /// `admin=true` in `.env` AND a debug build. Developer-only shortcuts must
  /// gate on this — the [kDebugMode] half means an `admin=true` file that
  /// slips into a release build still can't expose them.
  ///
  /// The [dotenv.isInitialized] check keeps widget tests (which don't run
  /// [load]) reading `false` instead of throwing.
  static bool get isAdmin =>
      kDebugMode &&
      dotenv.isInitialized &&
      dotenv.maybeGet('admin') == 'true';
}
