import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kadastr/features/home/user_profile.dart';
import 'package:kadastr/features/profile/profile_screen.dart';
import 'package:kadastr/widgets/app_menu_card.dart';

void main() {
  setUp(() {
    userProfileNotifier.value = null;
    notificationUnreadNotifier.value = 0;
  });

  testWidgets('renders name and phone from profile notifier', (tester) async {
    userProfileNotifier.value = const UserProfile(
      name: 'Odiljon Sanoyev',
      phone: '+998 90 123 45 67',
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pump();

    expect(find.text('Odiljon Sanoyev'), findsOneWidget);
    expect(find.text('+998 90 123 45 67'), findsOneWidget);
  });

  testWidgets('renders all six menu rows in uz locale', (tester) async {
    userProfileNotifier.value = const UserProfile(
      name: 'Odiljon',
      phone: '+998 90 000 00 00',
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pump();

    expect(find.byType(AppMenuRow), findsNWidgets(6));
    expect(find.text('Mening profilim'), findsOneWidget);
    expect(find.text('Mening skanerlarim'), findsOneWidget);
    expect(find.text('Baholashlarim'), findsOneWidget);
    expect(find.text("To'lovlar"), findsOneWidget);
    expect(find.text('Sozlamalar'), findsOneWidget);
    expect(find.text('Yordam'), findsOneWidget);
  });

  testWidgets('bell red dot appears only when unread > 0', (tester) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    notificationUnreadNotifier.value = 0;
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pump();
    expect(find.byKey(const ValueKey('profile.bell.dot')), findsNothing);

    notificationUnreadNotifier.value = 3;
    await tester.pump();
    expect(find.byKey(const ValueKey('profile.bell.dot')), findsOneWidget);
  });

  testWidgets('tapping a menu row triggers its callback', (tester) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    var settingsTapped = 0;
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(onSettingsTap: () => settingsTapped++)),
    );
    await tester.pump();

    await tester.tap(find.text('Sozlamalar'));
    await tester.pump();
    expect(settingsTapped, 1);
  });

  testWidgets('guest fallback shows Mehmon when profile is null', (
    tester,
  ) async {
    userProfileNotifier.value = null;
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pump();

    expect(find.text('Mehmon'), findsOneWidget);
  });

  testWidgets('ru locale renders Russian labels', (tester) async {
    userProfileNotifier.value = const UserProfile(name: 'Odiljon');
    await tester.pumpWidget(
      const MaterialApp(home: ProfileScreen(locale: Locale('ru'))),
    );
    await tester.pump();

    expect(find.text('Мой профиль'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Помощь'), findsOneWidget);
  });
}
