/// The app's version, in one place.
///
/// This existed twice before — a `_kAppVersion = '1.0.2'` const in the About
/// screen and a bare `'1.0.0 (4)'` literal in Settings — and the two had drifted
/// from each other *and* from pubspec (`1.0.2+18`). Two hand-typed copies of the
/// same fact will always diverge, so there is now exactly one.
///
/// It still has to be bumped by hand alongside pubspec's `version:`. Reading it
/// from the build instead (package_info_plus) would make drift impossible; that
/// needs a new dependency, so it's a deliberate follow-up rather than a silent
/// addition here.
library;

/// Marketing version — keep in sync with pubspec `version:` (before the `+`).
const String kAppVersion = '1.0.2';

/// Build number — the part after the `+` in pubspec `version:`.
const String kAppBuild = '19';

/// "1.0.2 (18)" — what both About and Settings display.
const String kAppVersionFull = '$kAppVersion ($kAppBuild)';
