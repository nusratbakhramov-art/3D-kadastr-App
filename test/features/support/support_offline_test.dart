// Internetsiz ochilganda Yordam sahifasi nimani ko'rsatadi.
//
// Xotiradagi kesh jarayon bilan birga o'ladi. Ilova YOPILIB, internetsiz
// qaytadan ochilsa, avval faqat zaxira raqam qolardi — telegram va pochta
// yo'qolardi, aynan ular kerak bo'lgan paytda. Endi oxirgi muvaffaqiyatli
// javob diskda saqlanadi.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/support/support_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _body =
    '{"phone":"1269","email":"3d.kadastr@gmail.com",'
    '"telegram":"@kadastr3_d","call_center":"1269"}';

SupportService online() => SupportService(
  client: MockClient((_) async => http.Response(_body, 200)),
);

SupportService offline() => SupportService(
  client: MockClient((_) async => throw const _NoNetwork()),
);

class _NoNetwork implements Exception {
  const _NoNetwork();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SupportService.resetCacheForTest();
  });

  test('online — backenddan keladi va diskka yoziladi', () async {
    final info = await online().fetchInfo();
    expect(info.telegram, '@kadastr3_d');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('support_info_v1'), contains('kadastr3_d'));
  });

  test('offline SOVUQ start — diskdagi oxirgi qiymat qaytadi', () async {
    await online().fetchInfo();          // bir marta muvaffaqiyatli
    SupportService.resetCacheForTest();  // ilova yopildi: xotira keshi yo'q

    final info = await offline().fetchInfo();
    expect(info.telegram, '@kadastr3_d', reason: 'telegram yo\'qolmasligi kerak');
    expect(info.email, '3d.kadastr@gmail.com');
    expect(info.callNumber, '1269');
  });

  test('offline va disk BO\'SH — zaxira raqam, ilova buzilmaydi', () async {
    final info = await offline().fetchInfo();
    expect(info.callNumber, SupportService.fallbackPhone);
    expect(info.telegram, isNull);
    expect(info.email, isNull);
  });

  test('server 500 — eski qiymat saqlanib qoladi', () async {
    await online().fetchInfo();
    SupportService.resetCacheForTest();
    final broken = SupportService(
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    expect((await broken.fetchInfo()).telegram, '@kadastr3_d');
  });
}
