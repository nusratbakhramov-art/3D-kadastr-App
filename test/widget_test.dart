import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kadastr/features/splash/animated_splash_screen.dart';
import 'package:kadastr/main.dart';

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
    await tester.pump(const Duration(milliseconds: 500));
    expect(completed, isTrue);
  });

  testWidgets('app transitions from splash to home', (tester) async {
    await tester.pumpWidget(const KadastrApp());

    await tester.pump();
    expect(find.text('3D kadastr'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2900));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Добро пожаловать'), findsOneWidget);
  });
}
