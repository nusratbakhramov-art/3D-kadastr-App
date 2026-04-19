import 'package:flutter/material.dart';
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

Future<void> _settleSplash(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2900));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 400));
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

    await tester.pump(const Duration(milliseconds: 2900));
    await tester.pump(const Duration(milliseconds: 700));
    expect(completed, isTrue);
  });

  testWidgets('returning user: splash → home', (tester) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    final storage = _FakeOnboardingStorage(initiallyCompleted: true);
    await tester.pumpWidget(KadastrApp(onboardingStorage: storage));

    await _settleSplash(tester);
    expect(find.text('3D kadastr'), findsOneWidget);
  });

  testWidgets('home: logged-in shows greeting with name and all four cards', (
    tester,
  ) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(MaterialApp(home: HomeScreen(today: _fixedDate)));
    await tester.pump();

    expect(find.textContaining('Salom, Odiljon'), findsOneWidget);
    expect(find.text('3D kadastr'), findsOneWidget);
    expect(find.text('AI baholash'), findsOneWidget);
    expect(find.text('Kalkulyator'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('14 aprel, 2026'), findsOneWidget);
  });

  testWidgets('home: guest shows guest greeting', (tester) async {
    userProfileNotifier.value = null;
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(MaterialApp(home: HomeScreen(today: _fixedDate)));
    await tester.pump();

    expect(find.textContaining('Salom, mehmon'), findsOneWidget);
    expect(find.text('Kirish'), findsNWidgets(2));
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
  });

  testWidgets('home: CTA shows headline and order button when logged-in', (
    tester,
  ) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(MaterialApp(home: HomeScreen(today: _fixedDate)));
    await tester.pump();

    expect(
      find.text('Professional skan + AI baholash + QR hisobot'),
      findsOneWidget,
    );
    expect(find.text('Buyurtma berish'), findsOneWidget);
  });

  testWidgets('home: CTA button reads Kirish when guest', (tester) async {
    userProfileNotifier.value = null;
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(MaterialApp(home: HomeScreen(today: _fixedDate)));
    await tester.pump();

    // Two 'Kirish' buttons visible in guest mode: header pill + CTA button.
    expect(find.text('Kirish'), findsNWidgets(2));
    expect(find.text('Buyurtma berish'), findsNothing);
  });

  testWidgets('home: bell shows red dot when unread > 0, hides when 0', (
    tester,
  ) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 2;
    await tester.pumpWidget(MaterialApp(home: HomeScreen(today: _fixedDate)));
    await tester.pump();
    expect(find.byKey(const ValueKey('home.bell.dot')), findsOneWidget);

    notificationUnreadNotifier.value = 0;
    await tester.pump();
    expect(find.byKey(const ValueKey('home.bell.dot')), findsNothing);
  });

  testWidgets('shell: renders all 5 tab labels', (tester) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(const MaterialApp(home: MainShell()));
    await tester.pump();

    expect(find.text('Asosiy'), findsOneWidget);
    expect(find.text('Xizmatlar'), findsOneWidget);
    expect(find.text('Arizalar'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('shell: tapping Xizmatlar swaps content', (tester) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(const MaterialApp(home: MainShell()));
    await tester.pump();

    // Home tab active by default.
    expect(find.text('3D kadastr'), findsOneWidget);

    await tester.tap(find.text('Xizmatlar'));
    await tester.pump();

    // Home content no longer visible (offstage inside IndexedStack).
    expect(find.text('3D kadastr'), findsNothing);
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
