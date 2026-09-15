import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/auth/widgets/login_required_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `ensureLoggedIn` — Home'dagi qulflangan kartalar (AI Baholash, Bozor AI,
/// Taqiqni tekshirish) mehmonni shu drawer bilan kutib oladi: ekran ochilmaydi,
/// «Kirish» / «Bekor qilish» tanlovi beriladi.
///
/// Yorliqlar bu yerda kalitning O'ZI bo'lib chiqadi
/// (`auth.login_required.title`): `tr()` bundle yuklanmagan holatda kalitni
/// qaytaradi.
void main() {
  /// Qulflangan amalni taqlid qiluvchi bitta tugma — natijani [onResult]'ga
  /// qaytaradi (true = davom etish mumkin).
  Future<void> pumpGate(
    WidgetTester tester,
    void Function(bool) onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => onResult(await ensureLoggedIn(context)),
                child: const Text('ochish'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('mehmon: drawer chiqadi, «Bekor qilish» — false', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    bool? result;
    await pumpGate(tester, (v) => result = v);

    await tester.tap(find.text('ochish'));
    await tester.pumpAndSettle();

    expect(find.text('auth.login_required.title'), findsOneWidget);
    expect(find.text('auth.login_required.sign_in'), findsOneWidget);

    await tester.tap(find.text('auth.login_required.cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('sessiya bor: drawer YO\'Q, darhol true', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_token_v1': 'test-token',
    });
    bool? result;
    await pumpGate(tester, (v) => result = v);

    await tester.tap(find.text('ochish'));
    await tester.pumpAndSettle();

    expect(find.text('auth.login_required.title'), findsNothing);
    expect(result, isTrue);
  });
}
