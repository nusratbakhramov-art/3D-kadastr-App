/// Marketplace e'lon matni — til qanday so'raladi va nima chiziladi.
///
/// Nega bu testlar bor:
///
///   * **Zaxira qoidasi ILOVADA YO'Q — ataylab.** Sarlavha/tavsif tanlovi
///     serverda hal qilinadi. Bu yerda tekshiriladigan narsa — ilova
///     JORIY tilini har so'rovda to'g'ri aytadimi va serverdan kelgan
///     matnni o'zgartirmasdan ko'rsatadimi. Agar kimdir kelajakda
///     "ru bo'lsa shuni oling" degan mantiqni Flutter'ga ko'chirsa, qoida
///     ikki joyda bo'lib qoladi va jimgina ajralib ketadi.
///   * **Til o'zgarsa so'rov ham o'zgarishi kerak.** Servis obyekti ekran
///     state'ida uzoq yashaydi; til bir marta ko'chirib olinsa, e'lon
///     tafsiloti eski tilda qotib qolardi.
///   * **Eski backend.** `content_locale` yubormaydigan server bilan ham
///     parsing yiqilmasligi kerak.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kadastr/features/market/api_market_repository.dart';
import 'package:kadastr/features/market/api_marketplace_service.dart';
import 'package:kadastr/features/market/market_controller.dart';
import 'package:kadastr/features/market/models/market_listing.dart';
import 'package:kadastr/features/market/widgets/listing_card.dart';
import 'package:kadastr/features/settings/settings_state.dart';

/// Har bir so'rovning sarlavhalarini yozib boradigan soxta klient.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.body);

  final Object body;
  final List<Map<String, String>> requests = [];
  final List<Uri> urls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(Map<String, String>.from(request.headers));
    urls.add(request.url);
    final payload = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.value(payload),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, dynamic> _item({
  int id = 1,
  required String name,
  String? description,
  String? contentLocale,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'category': 'residential',
    'region': 'Yashnobod',
    'area': '100.00',
    'description': description,
    'is_free': true,
    'price': null,
    'preview_image_url': null,
    'status': 'active',
    'scenes': <dynamic>[],
    'files': <dynamic>[],
    'created_at': '2026-09-23T00:00:00Z',
    'is_owned': false,
    // Eski backend bu kalitni umuman yubormaydi.
    'content_locale': ?contentLocale,
  };
}

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'size': 20,
};

void main() {
  final original = localeNotifier.value;
  tearDown(() => localeNotifier.value = original);

  group('til so\'rovga qo\'shiladi', () {
    test('Accept-Language ilovaning JORIY tilidan olinadi', () async {
      localeNotifier.value = const Locale('ru');
      final client = _RecordingClient(_page([_item(name: 'RU title')]));
      final service = MarketplaceApiService(
        client: client,
        baseUrl: 'http://t/api/v1',
      );

      await service.listModels();

      expect(client.requests.single['Accept-Language'], 'ru');
    });

    test('til almashsa KEYINGI so\'rov yangi tilda ketadi', () async {
      // Servis bir marta quriladi va ekran state'ida qoladi — til esa
      // sozlamalardan istalgan payt o'zgaradi.
      localeNotifier.value = const Locale('uz');
      final client = _RecordingClient(_page([_item(name: 'x')]));
      final service = MarketplaceApiService(
        client: client,
        baseUrl: 'http://t/api/v1',
      );

      await service.listModels();
      localeNotifier.value = const Locale('en');
      await service.listModels();

      expect(client.requests.map((h) => h['Accept-Language']).toList(), [
        'uz',
        'en',
      ]);
    });

    test('detal so\'rovi ham tilni olib boradi', () async {
      localeNotifier.value = const Locale('en');
      final client = _RecordingClient(_item(name: 'EN title'));
      final service = MarketplaceApiService(
        client: client,
        baseUrl: 'http://t/api/v1',
      );

      await service.getModel(7);

      expect(client.requests.single['Accept-Language'], 'en');
      expect(client.urls.single.path, endsWith('/marketplace/7'));
    });

    test(
      'konstruktordagi til ilova tilidan ustun (testlar/DI uchun)',
      () async {
        localeNotifier.value = const Locale('uz');
        final client = _RecordingClient(_page([_item(name: 'x')]));
        final service = MarketplaceApiService(
          client: client,
          baseUrl: 'http://t/api/v1',
          locale: 'ru',
        );

        await service.listModels();

        expect(client.requests.single['Accept-Language'], 'ru');
      },
    );

    test('repozitoriy ham o\'sha servisdan foydalanadi', () async {
      localeNotifier.value = const Locale('ru');
      final client = _RecordingClient(_page([_item(name: 'RU title')]));
      final repo = ApiMarketRepository(
        service: MarketplaceApiService(
          client: client,
          baseUrl: 'http://t/api/v1',
        ),
      );

      final page = await repo.fetchPage(
        query: '',
        categoryId: 'all',
        offset: 0,
        limit: 20,
      );

      expect(client.requests.single['Accept-Language'], 'ru');
      expect(page.items.single.title, 'RU title');
    });
  });

  group('javob o\'zgartirilmasdan olinadi', () {
    test('serverdan kelgan matn — ilova uni qayta tanlamaydi', () async {
      // Server ruscha so'rovga o'zbekcha matn qaytardi (chala tarjima).
      // Ilova buni SHUNDAYLIGICHA ko'rsatishi kerak.
      localeNotifier.value = const Locale('ru');
      final client = _RecordingClient(
        _item(
          name: 'UZ partial title',
          description: 'UZ partial description',
          contentLocale: 'uz',
        ),
      );
      final service = MarketplaceApiService(
        client: client,
        baseUrl: 'http://t/api/v1',
      );

      final listing = await service.getModel(3);

      expect(listing.title, 'UZ partial title');
      expect(listing.description, 'UZ partial description');
      expect(listing.contentLocale, 'uz');
    });

    test('`content_locale` yubormaydigan ESKI backend yiqitmaydi', () async {
      final client = _RecordingClient(_item(name: 'Eski javob'));
      final service = MarketplaceApiService(
        client: client,
        baseUrl: 'http://t/api/v1',
      );

      final listing = await service.getModel(1);

      expect(listing.title, 'Eski javob');
      // O'shanda matn o'zbekcha edi — zaxira qiymat shunga mos.
      expect(listing.contentLocale, 'uz');
    });

    test('bo\'sh tavsif null bo\'lib qoladi, "null" matni emas', () async {
      final client = _RecordingClient(_item(name: 'Nom', description: null));
      final service = MarketplaceApiService(
        client: client,
        baseUrl: 'http://t/api/v1',
      );

      expect((await service.getModel(1)).description, isNull);
    });
  });

  group('umumiy kontroller til bilan bog\'langan', () {
    test('til o\'zgarsa YANGI kontroller qaytadi (ro\'yxat qayta olinadi)', () {
      // Bozor ekrani `PageView` ichida yashaydi: til almashganda `initState`
      // qayta ishlamaydi, shuning uchun keshdagi e'lonlarni yangi til bilan
      // qayta so'rashning yagona yo'li — kontrollerni almashtirish.
      final uz = sharedMarketController(locale: 'uz');
      final sameAgain = sharedMarketController(locale: 'uz');
      expect(identical(uz, sameAgain), isTrue, reason: 'til o\'zgarmadi');

      final ru = sharedMarketController(locale: 'ru');
      expect(identical(ru, uz), isFalse);
    });
  });

  group('kartochka serverdagi sarlavhani chizadi', () {
    Future<void> pump(WidgetTester tester, MarketListing listing) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 320,
              child: ListingCard(listing: listing, onTap: (_) {}),
            ),
          ),
        ),
      );
    }

    MarketListing listing(String title, String contentLocale) => MarketListing(
      id: '1',
      imageUrl: '',
      priceUzs: 0,
      title: title,
      district: 'Yashnobod',
      areaM2: 100,
      categoryId: 'residential',
      isFree: true,
      contentLocale: contentLocale,
    );

    testWidgets('ruscha matn ruscha chiqadi', (tester) async {
      await pump(tester, listing('RU multilingual title', 'ru'));
      expect(find.text('RU multilingual title'), findsOneWidget);
    });

    testWidgets('inglizcha matn inglizcha chiqadi', (tester) async {
      await pump(tester, listing('EN multilingual title', 'en'));
      expect(find.text('EN multilingual title'), findsOneWidget);
    });

    testWidgets('zaxiraga tushgan o\'zbekcha matn ham o\'zgarmaydi', (
      tester,
    ) async {
      // Ilova tili ruscha, lekin server o'zbekcha blok qaytardi.
      localeNotifier.value = const Locale('ru');
      await pump(tester, listing('UZ legacy title', 'uz'));
      expect(find.text('UZ legacy title'), findsOneWidget);
    });
  });
}
