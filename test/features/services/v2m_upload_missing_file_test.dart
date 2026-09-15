import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/services/data/v2m_client.dart';

/// Yuklash boshlanmasidan oldingi tekshiruvlar.
///
/// NEGA MUHIM: `CapturedRoom.videoPath` `SharedPreferences` da saqlanadi,
/// lekin iOS tmp/Caches ni tozalaydi va ilova qayta o'rnatilganda konteyner
/// nomi o'zgaradi — saqlangan mutlaq yo'l muntazam ravishda "o'lik" bo'lib
/// qoladi.
///
/// Ilgari `upload()` ning birinchi qatori himoyalanmagan `file.length()` edi.
/// Yo'q fayl `PathNotFoundException` tashlardi, chaqiruvchi esa FAQAT
/// [V2mException] ni ushlagani uchun xato undan o'tib ketardi va ekran
/// "Video yuklanmoqda — 0.0 / 0.0 MB" holatida abadiy qotib qolardi
/// (`onProgress` bir marta ham chaqirilmagani uchun 0/0).
void main() {
  /// So'rov TARMOQQA CHIQMASLIGI kerak — tekshiruvlar undan oldin ishlaydi.
  /// Mijoz chaqirilsa test yiqiladi.
  final client = MockClient((request) async {
    fail('tarmoqqa chiqmasligi kerak edi: ${request.url}');
  });

  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('v2m_upload_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  V2mClient makeClient() =>
      V2mClient(baseUrl: 'https://example.invalid', client: client);

  test('yo\'q fayl — V2mException(NO_FILE), FileSystemException emas', () async {
    final missing = File('${tmp.path}/never_written.mov');
    expect(missing.existsSync(), isFalse);

    await expectLater(
      makeClient().upload(file: missing, name: 'Ariza 1 · Mehmonxona'),
      throwsA(
        isA<V2mException>().having((e) => e.code, 'code', 'NO_FILE'),
      ),
    );
  });

  test('bo\'sh fayl ham yuborilmaydi', () async {
    final empty = File('${tmp.path}/empty.mov')..createSync();
    expect(empty.lengthSync(), 0);

    await expectLater(
      makeClient().upload(file: empty, name: 'Ariza 1 · Mehmonxona'),
      throwsA(
        isA<V2mException>().having((e) => e.code, 'code', 'EMPTY_FILE'),
      ),
    );
  });

  /// Ikkinchi shikoyat: "0 MB ko'rsatyapti, lekin videolar katta hajmli".
  /// Sabab — hajm faqat BIRINCHI bayt oqqanda bildirilardi, ulanish sekin
  /// ochilsa esa ekran "0.0 / 0.0 MB" bo'lib turardi.
  test('hajm birinchi baytdan oldin bildiriladi', () async {
    final video = File('${tmp.path}/room.mov')
      ..writeAsBytesSync(List<int>.filled(4096, 7));
    final seen = <List<int>>[];

    final stalling = MockClient((_) async {
      // Server javob bermayapti — aynan foydalanuvchi ko'rgan holat.
      throw const SocketException('stalled');
    });

    await expectLater(
      V2mClient(baseUrl: 'https://example.invalid', client: stalling).upload(
        file: video,
        name: 'Ariza 1 · Mehmonxona',
        onProgress: (sent, total) => seen.add([sent, total]),
      ),
      throwsA(isA<V2mException>()),
    );

    expect(seen, isNotEmpty, reason: 'hajm darhol bildirilishi kerak');
    expect(seen.first, [0, 4096],
        reason: 'birinchi xabar 0/haqiqiy-hajm bo\'lishi kerak, 0/0 emas');
  });

  test('yo\'q fayl uchun onProgress umuman chaqirilmaydi', () async {
    // Aynan shu sabab ekranda "0.0 / 0.0 MB" turardi: progress kelmaydi,
    // shuning uchun xato KO'RINADIGAN holatga aylanishi shart.
    var calls = 0;
    await expectLater(
      makeClient().upload(
        file: File('${tmp.path}/nope.mov'),
        name: 'x',
        onProgress: (_, _) => calls++,
      ),
      throwsA(isA<V2mException>()),
    );
    expect(calls, 0);
  });

  /// Server 200 sarlavhasini qaytarib, TANANI yubormay jim qolsa.
  /// `.timeout()` faqat `send()` ni (sarlavhalarni) qoplardi, tana o'qish
  /// esa chegarasiz edi — future umuman tugallanmasdi, ya'ni hech qanday
  /// `catch` ishlamasdi va ekran "yuklanmoqda" da qamalib qolardi.
  test('server tanani yubormasa ham upload tugaydi', () async {
    final video = File('${tmp.path}/room.mov')
      ..writeAsBytesSync(List<int>.filled(1024, 3));

    final stalled = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      // Hech qachon yopilmaydigan oqim — osilgan serverning aksi.
      return http.StreamedResponse(
        StreamController<List<int>>().stream,
        200,
      );
    });

    await expectLater(
      V2mClient(
        baseUrl: 'https://example.invalid',
        client: stalled,
        readTimeout: const Duration(milliseconds: 200),
      ).upload(
        file: video,
        name: 'Ariza 1 · Mehmonxona',
      ),
      throwsA(isA<V2mException>().having((e) => e.code, 'code', 'TIMEOUT')),
    );
  });
}
