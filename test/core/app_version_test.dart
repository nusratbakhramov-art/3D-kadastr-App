/// The version a user reads on About/Settings comes from `app_version.dart`,
/// but the version the store sees comes from `pubspec.yaml`. Nothing keeps the
/// two honest, and they have already drifted once: Settings showed a hardcoded
/// "1.0.0 (4)" while the app shipped as 1.0.2+17. Since the drift is silent and
/// only ever noticed by a user reading the wrong number back to support, pin it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/app_version.dart';

void main() {
  test('app_version.dart matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);

    expect(line, isNotNull, reason: 'no version: line in pubspec.yaml');

    final parts = line!.split('+');
    expect(
      parts,
      hasLength(2),
      reason: 'pubspec version should be <version>+<build>, got "$line"',
    );

    expect(
      parts[0],
      kAppVersion,
      reason: 'pubspec version ${parts[0]} != kAppVersion $kAppVersion — bump '
          'both, or the store and the About screen disagree',
    );
    expect(
      parts[1],
      kAppBuild,
      reason: 'pubspec build ${parts[1]} != kAppBuild $kAppBuild — bump both',
    );
  });

  test('kAppVersionFull reads the way the About chip shows it', () {
    expect(kAppVersionFull, '$kAppVersion ($kAppBuild)');
  });
}
