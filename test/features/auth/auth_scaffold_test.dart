import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/widgets/auth_scaffold.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: child),
  );

  testWidgets('renders title and body', (tester) async {
    await tester.pumpWidget(
      wrap(
        AuthScaffold(
          title: 'Ilovaga kiring',
          iconAsset: 'assets/images/auth/login.png',
          onBack: () {},
          onSkip: () {},
          body: const Text('BODY'),
        ),
      ),
    );
    expect(find.text('Ilovaga kiring'), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
    expect(find.text("O'tkazib yuborish"), findsOneWidget);
  });

  testWidgets('back fires onBack', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(
        AuthScaffold(
          title: 't',
          iconAsset: 'assets/images/auth/login.png',
          onBack: () => tapped++,
          onSkip: () {},
          body: const SizedBox(),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('auth.back')));
    expect(tapped, 1);
  });

  testWidgets('skip fires onSkip', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(
        AuthScaffold(
          title: 't',
          iconAsset: 'assets/images/auth/login.png',
          onBack: () {},
          onSkip: () => tapped++,
          body: const SizedBox(),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('auth.skip')));
    expect(tapped, 1);
  });

  testWidgets('hides back when onBack is null', (tester) async {
    await tester.pumpWidget(
      wrap(
        AuthScaffold(
          title: 't',
          iconAsset: 'assets/images/auth/login.png',
          onBack: null,
          onSkip: () {},
          body: const SizedBox(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('auth.back')), findsNothing);
  });
}
