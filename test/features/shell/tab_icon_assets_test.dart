import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four bottom-nav glyphs are hand-authored / traced SVGs, and two of them
/// (Market, Arizalar) carry brand artwork with arcs, a negative viewBox origin
/// and evenodd fills. This asserts flutter_svg's parser actually accepts them,
/// which a plain `flutter analyze` cannot tell us.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assets = <String>[
    'assets/icons/tab-home.svg',
    'assets/icons/tab-market.svg',
    'assets/icons/tab-applications.svg',
    'assets/icons/tab-profile.svg',
  ];

  for (final asset in assets) {
    test('$asset parses and has a non-empty picture', () async {
      final source = await File(asset).readAsString();
      final info = await vg.loadPicture(SvgStringLoader(source), null);
      addTearDown(info.picture.dispose);
      expect(info.size.width, greaterThan(0));
      expect(info.size.height, greaterThan(0));
    });
  }
}
