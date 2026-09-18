// "Hammasini o'qilgan deb belgilash" backendga so'rov yuboradi, shuning uchun
// natijasi KO'RINISHI shart. Avval javob kodi umuman tekshirilmasdi: server
// 500 qaytarsa ham amal bajarilgan deb hisoblanardi va foydalanuvchi
// o'qilmagan xabarlari yo'qolgan deb o'ylardi.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/notifications/notifications_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

NotificationsApi apiReturning(int status) => NotificationsApi(
  client: MockClient((_) async => http.Response('', status)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token_v1': 'test-token'});
  });

  test('204 — muvaffaqiyat, otmaydi', () async {
    await expectLater(apiReturning(204).markAllRead(), completes);
  });

  test('500 — OTADI, jimgina muvaffaqiyat emas', () async {
    await expectLater(apiReturning(500).markAllRead(), throwsA(isA<Exception>()));
  });

  test('401 ham otadi', () async {
    await expectLater(apiReturning(401).markAllRead(), throwsA(isA<Exception>()));
  });

  test("login yo'q — so'rov umuman ketmaydi", () async {
    SharedPreferences.setMockInitialValues({});
    var called = false;
    final api = NotificationsApi(
      client: MockClient((_) async {
        called = true;
        return http.Response('', 500);
      }),
    );
    await api.markAllRead();
    expect(called, isFalse);
  });
}
