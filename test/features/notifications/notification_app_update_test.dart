// `app_update` bildirishnomasi ro'yxatda ham do'konga olib borishi kerak.
//
// Avval push'ni bosish do'konni ochardi, lekin ro'yxatdagi O'SHA xabarni
// ochganda hech narsa bo'lmasdi — bitta xabarning ikki yo'li ikki xil
// ishlardi. Quyidagi testlar turning saqlanishini va tugmaning faqat shu
// turda chiqishini qulflaydi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/notifications/notification_detail_screen.dart';
import 'package:kadastr/features/notifications/notification_model.dart';

AppNotification _n(String type) => AppNotification.fromJson({
  'id': 1,
  'notification_type': type,
  'title': 'Yangi versiya 1.0.6',
  'message': 'Yangilang',
  'created_at': DateTime.now().toIso8601String(),
  'is_read': false,
});

void main() {
  test('app_update o\'z turiga tushadi — system emas', () {
    expect(_n('app_update').type, NotificationType.appUpdate);
  });

  test('noma\'lum tur hamon system bo\'lib qoladi', () {
    expect(_n('something_new').type, NotificationType.system);
    expect(_n(null.toString()).type, NotificationType.system);
  });

  test('mavjud turlar buzilmagan', () {
    expect(_n('payment_status').type, NotificationType.payment);
    expect(_n('scan_completed').type, NotificationType.scan);
    expect(_n('valuation_done').type, NotificationType.valuation);
    expect(_n('moderation_result').type, NotificationType.listing);
  });

  test('appUpdate o\'z ikonkasiga ega — umumiy info emas', () {
    final (updateIcon, _) = iconForType(NotificationType.appUpdate);
    final (systemIcon, _) = iconForType(NotificationType.system);
    expect(updateIcon, isNot(systemIcon));
    expect(updateIcon, Icons.system_update_alt_rounded);
  });

  group('detal ekrani', _uiTests);
}

/// Ro'yxatdan ochilgan `app_update` xabarida "Yangilash" tugmasi BO'LISHI
/// kerak — aynan shu yetishmayotgan edi.
void _uiTests() {
  setUp(() {
    appTranslationsNotifier.value = const AppTranslations(
      version: 1,
      byLang: {
        'uz': {
          'update.action_update': 'Yangilash',
          'notifications.detail_title': 'Bildirishnoma',
        },
      },
    );
  });

  Widget screen(AppNotification n) => MaterialApp(
    locale: const Locale('uz'),
    home: NotificationDetailScreen(item: n),
  );

  testWidgets('app_update xabarida do\'kon tugmasi chiqadi', (t) async {
    await t.pumpWidget(screen(_n('app_update')));
    await t.pump();
    expect(find.text('Yangilash'), findsOneWidget);
  });

  testWidgets('oddiy xabarda tugma YO\'Q', (t) async {
    await t.pumpWidget(screen(_n('payment_status')));
    await t.pump();
    expect(find.text('Yangilash'), findsNothing);
  });
}
