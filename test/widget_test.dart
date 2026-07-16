import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kadastr/features/home/home_screen.dart';
import 'package:kadastr/features/home/user_profile.dart';
import 'package:kadastr/features/onboarding/onboarding_screen.dart';
import 'package:kadastr/features/onboarding/onboarding_storage.dart';
import 'package:kadastr/features/shell/main_shell.dart';
import 'package:kadastr/features/splash/animated_splash_screen.dart';
import 'package:kadastr/main.dart';

class _FakeOnboardingStorage implements OnboardingStorage {
  _FakeOnboardingStorage({required this.initiallyCompleted});

  bool initiallyCompleted;
  bool markCompletedCalled = false;

  @override
  Future<bool> hasCompleted() async => initiallyCompleted;

  @override
  Future<void> markCompleted() async {
    markCompletedCalled = true;
    initiallyCompleted = true;
  }

  @override
  Future<void> reset() async {
    initiallyCompleted = false;
  }
}

final DateTime _fixedDate = DateTime(2026, 4, 14);

/// Silences the plugins KadastrApp touches on boot.
///
/// There is no platform side under flutter_test, so each of these throws
/// MissingPluginException and the binding reports it as a test failure. They
/// only surface once a test lets real platform-channel work run (i.e. inside
/// runAsync), so they look like new breaks when they aren't.
void _stubBootPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // app_links — deep links.
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.app_links/messages'),
    (call) async => null,
  );
  messenger.setMockStreamHandler(
    const EventChannel('com.llfbandit.app_links/events'),
    MockStreamHandler.inline(onListen: (args, sink) {}),
  );

  // shared_preferences — locale, onboarding flag, cached i18n bundle.
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async => call.method == 'getAll' ? <String, Object>{} : null,
  );

  // app_badge_plus — unread badge synced on boot.
  messenger.setMockMethodCallHandler(
    const MethodChannel('app_badge_plus'),
    (call) async => call.method == 'isSupported' ? false : null,
  );
}

/// Advances past the splash.
///
/// The screen straddles both of the test's clocks, so this has to as well:
///   1. It decodes 36 webp frames before calling forward(). That is real async
///      I/O which pump()'s fake clock cannot drive, so it needs runAsync.
///   2. The 3800ms controller then ticks on the *fake* clock, which does not
///      advance inside runAsync — so it needs pump().
///   3. onComplete fires from a Future.delayed(350ms) scheduled during that
///      fake-clock frame, so it needs one more pump to actually run.
/// Miss any step and onComplete never fires.
Future<void> _settleSplash(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 3900));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpHome(WidgetTester tester, {DateTime? today}) async {
  await tester.pumpWidget(
    MaterialApp(home: HomeScreen(today: today ?? _fixedDate)),
  );
  await tester.pump();
}

/// Drains the fetches HomeScreen fires on mount.
///
/// It asks for support info (10s timeout), the i18n bundle (12s) and the market
/// data (15s per call, chained). None resolve under flutter_test, so their
/// `Future.timeout` timers stay armed and teardown trips its "a Timer is still
/// pending" invariant — failing the test even when every assertion passed.
///
/// 40s, measured: the market controller's chained calls still have a timer
/// pending at 20s. Only the *first* test to mount home pays this, because
/// sharedMarketController is a singleton — which is why the suite used to be
/// order-dependent, passing as a batch and failing a test on its own.
/// Pumping the fake clock is instant, so the wide window costs nothing.
Future<void> _drainHomeTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 40));
}

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  required VoidCallback onFinished,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OnboardingScreen(
        onFinished: onFinished,
        segmentDuration: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('splash shows brand mark and fires onComplete', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedSplashScreen(onComplete: () => completed = true),
      ),
    );

    await tester.pump();
    expect(find.text('3D kadastr'), findsOneWidget);

    await _settleSplash(tester);
    expect(completed, isTrue);
  });

  testWidgets('returning user: splash → home', (tester) async {
    _stubBootPlugins();
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    final storage = _FakeOnboardingStorage(initiallyCompleted: true);
    await tester.pumpWidget(KadastrApp(onboardingStorage: storage));

    await _settleSplash(tester);
    // The splash renders "3D kadastr" too, so assert on something only the
    // home screen has — otherwise this passes without ever leaving the splash,
    // which is exactly what it used to do.
    expect(find.textContaining('Salom, Odiljon'), findsOneWidget);
    expect(find.text('Ai Kalkulyator'), findsOneWidget);
    await _drainHomeTimers(tester);
  });

  testWidgets('home: logged-in shows greeting with name and the three cards', (
    tester,
  ) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    await _pumpHome(tester);

    expect(find.textContaining('Salom, Odiljon'), findsOneWidget);
    // Ai baholash sits left of 3D kadastr; Market is a bottom tab, not a card.
    expect(find.text('Ai baholash'), findsOneWidget);
    expect(find.text('3D kadastr'), findsOneWidget);
    expect(find.text('Ai Kalkulyator'), findsOneWidget);
    expect(find.text('14 aprel, 2026'), findsOneWidget);

    final ai = tester.getRect(find.text('Ai baholash'));
    final kadastr = tester.getRect(find.text('3D kadastr'));
    expect(ai.left, lessThan(kadastr.left));
    await _drainHomeTimers(tester);
  });

  testWidgets('home: guest shows guest greeting', (tester) async {
    userProfileNotifier.value = null;
    notificationUnreadNotifier.value = 0;
    await _pumpHome(tester);

    expect(find.textContaining('Salom, mehmon'), findsOneWidget);
    // One 'Kirish' — the header pill. The CTA banner that carried the second
    // one was removed along with the Services page.
    expect(find.text('Kirish'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    await _drainHomeTimers(tester);
  });

  testWidgets('home: bell shows red dot when unread > 0, hides when 0', (
    tester,
  ) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 2;
    await _pumpHome(tester);
    expect(find.byKey(const ValueKey('home.bell.dot')), findsOneWidget);

    notificationUnreadNotifier.value = 0;
    await tester.pump();
    expect(find.byKey(const ValueKey('home.bell.dot')), findsNothing);
    await _drainHomeTimers(tester);
  });

  testWidgets('shell: renders all 4 tab labels', (tester) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(const MaterialApp(home: MainShell()));
    await tester.pump();

    // The Services ("Xizmatlar") tab is gone — Market took its slot.
    expect(find.text('Asosiy'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Arizalar'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
    // The shell mounts home behind the tabs, so it inherits its fetches.
    await _drainHomeTimers(tester);
  });

  testWidgets('shell: tapping Market swaps content', (tester) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(const MaterialApp(home: MainShell()));
    await tester.pump();

    // Home tab active by default; Market appears once (nav label only).
    expect(find.text('3D kadastr'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);

    await tester.tap(find.text('Market'));
    // Explicit pumps, not pumpAndSettle: on a cold market controller the screen
    // shows a loading shimmer that never stops, and pumpAndSettle waits for all
    // animation to cease — so it times out. It only survived before because the
    // controller is a singleton that an earlier test had already filled.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // After the slide, Market appears twice (nav label + screen title).
    expect(find.text('Market'), findsNWidgets(2));
    await _drainHomeTimers(tester);
  });

  testWidgets('onboarding: continue button advances through all pages', (
    tester,
  ) async {
    var finished = false;
    await _pumpOnboarding(tester, onFinished: () => finished = true);

    expect(find.text('3D KADASTR XIZMATI'), findsOneWidget);
    expect(find.text('Davom etish'), findsOneWidget);
    expect(find.text('Ortga'), findsNothing);

    await tester.tap(find.text('Davom etish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('AI BAHOLASH'), findsOneWidget);
    expect(find.text('Ortga'), findsOneWidget);

    await tester.tap(find.text('Davom etish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('MARKET VA KALKULYATOR'), findsOneWidget);

    await tester.tap(find.text('Davom etish'));
    await tester.pump();
    expect(finished, isTrue);
  });

  testWidgets('onboarding: back button rewinds one page', (tester) async {
    await _pumpOnboarding(tester, onFinished: () {});

    await tester.tap(find.text('Davom etish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('AI BAHOLASH'), findsOneWidget);

    await tester.tap(find.text('Ortga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('3D KADASTR XIZMATI'), findsOneWidget);
    expect(find.text('Ortga'), findsNothing);
  });

  testWidgets('onboarding: segment auto-advances after its duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinished: () {},
          segmentDuration: const Duration(milliseconds: 200),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('3D KADASTR XIZMATI'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('AI BAHOLASH'), findsOneWidget);
  });

  testWidgets('onboarding: last page does not auto-finish on timer', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinished: () => finished = true,
          segmentDuration: const Duration(milliseconds: 100),
        ),
      ),
    );
    await tester.pump();

    // Let all 3 segments auto-fill.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('MARKET VA KALKULYATOR'), findsOneWidget);
    expect(finished, isFalse);

    await tester.tap(find.text('Davom etish'));
    await tester.pump();
    expect(finished, isTrue);
  });

  testWidgets('onboarding: skip fires onFinished', (tester) async {
    var finished = false;
    await _pumpOnboarding(tester, onFinished: () => finished = true);

    await tester.tap(find.text("O'tkazib yuborish"));
    await tester.pump();
    expect(finished, isTrue);
  });
}
