import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/models/bozor_listing.dart';

/// E'lonni O'QISH modeli — `ListingOut` javobining parsingi.
///
/// Fixture'lar QO'LDA to'qilmagan: ular lokal backenddan olingan HAQIQIY
/// javoblar (`GET /api/v1/listings/1` va egasi uchun `ListingOut` dump'i,
/// 2026-09-10). Shuning uchun `Decimal` maydonlar SATR bo'lib turadi
/// (`"price_amount": "4500000.00"`), `params` ichida esa oddiy son — model
/// ikkalasini ham ko'tarishi kerak.
///
/// Media URL'lari nisbiy (`/kadastr-3d-files/...`), chunki lokalda S3
/// sozlanmagan — bu NORMAL va shu holatda ham parsing ishlashi kerak.

/// `GET /listings/1` — tasdiqlangan, 3 fayl (2 foto + planirovka).
const _approvedJson = '''
{
  "id": 1,
  "status": "approved",
  "title": "Chilonzorda 3 xonali kvartira",
  "deal_type": "rent",
  "property_kind": "residential",
  "property_type": "apartment",
  "region_id": null,
  "district_id": null,
  "region_name": null,
  "district_name": null,
  "address": "Toshkent sh., Chilonzor tumani, 12-kvartal",
  "landmark": "Metro yonida",
  "apartment_number": "45",
  "entrance": "2",
  "house_number": "18",
  "floor": 5,
  "total_floors": 9,
  "latitude": "41.285600",
  "longitude": "69.203400",
  "rooms": 3,
  "area_sqm": "78.50",
  "params": {
    "rooms_count": "3",
    "total_area": 78.5,
    "living_area": 52.0,
    "renovation": "euro",
    "freight_elevator": false,
    "gas": true,
    "parking": "yard"
  },
  "price_amount": "4500000.00",
  "price_currency": "UZS",
  "price_period": "month",
  "price_uzs": "4500000.00",
  "negotiable": true,
  "daily_amount": "350000.00",
  "daily_currency": "UZS",
  "description": "Yorug', ta'mirlangan kvartira.",
  "youtube_url": "https://youtu.be/xyz",
  "contact_name": "Abdulboriy",
  "contact_phone": "901234567",
  "contact_phones": ["901234567", "935556677"],
  "contact_email": "a@b.uz",
  "contact_phone_verified": false,
  "tier": "standard",
  "top_rank": 0,
  "rejection_reason": null,
  "moderated_at": "2026-09-10T08:25:35.894924Z",
  "published_at": "2026-09-10T08:25:35.894924Z",
  "media": [
    {
      "id": 1,
      "role": "photo",
      "url": "/kadastr-3d-files/listings/media/3/aaaaaaaaaaaa.jpg",
      "thumb_url": null,
      "is_cover": true,
      "sort_order": 0
    },
    {
      "id": 2,
      "role": "photo",
      "url": "/kadastr-3d-files/listings/media/3/bbbbbbbbbbbb.jpg",
      "thumb_url": null,
      "is_cover": false,
      "sort_order": 1
    },
    {
      "id": 3,
      "role": "plan",
      "url": "/kadastr-3d-files/listings/media/3/cccccccccccc.pdf",
      "thumb_url": null,
      "is_cover": false,
      "sort_order": 2
    }
  ],
  "created_at": "2026-09-10T08:25:35.882749Z"
}
''';

/// Egasining `GET /listings/my` javobidagi qator: moderatsiyada, MEDIA YO'Q,
/// ixtiyoriy maydonlarning hammasi `null`, narx dollarda va davri yo'q.
const _pendingNoMediaJson = '''
{
  "id": 2,
  "status": "pending",
  "title": "Ofis ijaraga",
  "deal_type": "rent",
  "property_kind": "residential",
  "property_type": "apartment",
  "region_id": null,
  "district_id": null,
  "region_name": null,
  "district_name": null,
  "address": "Samarqand sh., Registon ko'chasi 5",
  "landmark": null,
  "apartment_number": null,
  "entrance": null,
  "house_number": null,
  "floor": null,
  "total_floors": null,
  "latitude": null,
  "longitude": null,
  "rooms": 1,
  "area_sqm": "30.00",
  "params": {
    "rooms_count": "1",
    "total_area": 30.0,
    "living_area": 20.0,
    "freight_elevator": false,
    "gas": false,
    "parking": "none"
  },
  "price_amount": "1200.00",
  "price_currency": "USD",
  "price_period": null,
  "price_uzs": "14400000.00",
  "negotiable": false,
  "daily_amount": null,
  "daily_currency": null,
  "description": null,
  "youtube_url": null,
  "contact_name": "Dilshod",
  "contact_phone": "977778899",
  "contact_phones": ["977778899"],
  "contact_email": null,
  "contact_phone_verified": false,
  "tier": "standard",
  "top_rank": 0,
  "rejection_reason": null,
  "moderated_at": null,
  "published_at": null,
  "media": [],
  "created_at": "2026-09-10T08:25:35.882749Z"
}
''';

/// Rad etilgan e'lon — `rejection_reason` FAQAT egasiga keladi.
const _rejectedJson = '''
{
  "id": 3,
  "status": "rejected",
  "title": "Rad etilgan e'lon",
  "deal_type": "rent",
  "property_kind": "residential",
  "property_type": "apartment",
  "address": "Toshkent sh., Yunusobod 14-mavze",
  "rooms": 2,
  "area_sqm": "55.00",
  "params": {"rooms_count": "2", "total_area": 55.0},
  "price_amount": "3000000.00",
  "price_currency": "UZS",
  "price_period": "month",
  "price_uzs": "3000000.00",
  "negotiable": true,
  "contact_name": "Test",
  "contact_phone": "900000000",
  "contact_phones": ["900000000"],
  "contact_phone_verified": false,
  "tier": "standard",
  "top_rank": 0,
  "rejection_reason": "Rasmlar sifatsiz",
  "moderated_at": "2026-09-10T08:26:06.010939Z",
  "published_at": null,
  "media": [],
  "created_at": "2026-09-10T08:26:06.000760Z"
}
''';

Map<String, dynamic> _decode(String s) =>
    jsonDecode(s) as Map<String, dynamic>;

void main() {
  const uz = Locale('uz');

  setUpAll(() {
    // Yorliqli getter'lar HAQIQIY bundle bilan sinaladi: `tr()` kalit
    // topilmasa kalitning O'ZINI qaytaradi, ya'ni bundle'ga kalit qo'shish
    // esdan chiqsa test aynan shu joyda yiqiladi.
    final raw = File('assets/i18n/bundle.json').readAsStringSync();
    appTranslationsNotifier.value = AppTranslations.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  });

  group('BozorListing.fromJson', () {
    test('to‘liq javob: Decimal satrlari, media, params, sanalar', () {
      final l = BozorListing.fromJson(_decode(_approvedJson));

      expect(l.id, 1);
      expect(l.status, ListingStatus.approved);
      expect(l.statusCode, 'approved');
      expect(l.title, 'Chilonzorda 3 xonali kvartira');
      expect(l.dealType, 'rent');
      expect(l.propertyType, 'apartment');

      // Decimal → satr bo'lib keladi.
      expect(l.priceAmount, 4500000);
      expect(l.priceUzs, 4500000);
      expect(l.areaSqm, 78.5);
      expect(l.dailyAmount, 350000);
      expect(l.latitude, closeTo(41.2856, 1e-6));
      expect(l.longitude, closeTo(69.2034, 1e-6));

      expect(l.rooms, 3);
      expect(l.floor, 5);
      expect(l.totalFloors, 9);
      expect(l.negotiable, isTrue);
      expect(l.pricePeriod, 'month');
      expect(l.landmark, 'Metro yonida');
      expect(l.apartmentNumber, '45');
      expect(l.contactPhones, ['901234567', '935556677']);
      expect(l.contactEmail, 'a@b.uz');
      expect(l.youtubeUrl, 'https://youtu.be/xyz');
      expect(l.rejectionReason, isNull);
      expect(l.tier, 'standard');
      expect(l.isTop, isFalse);

      // `params` xom holda saqlanadi — kalitlari `param_schema.dart` dagidek.
      expect(l.params['renovation'], 'euro');
      expect(l.params['gas'], true);
      expect(l.params['total_area'], 78.5);

      // Sanalar UTC'dan lokalga o'giriladi.
      expect(l.createdAt.isUtc, isFalse);
      expect(l.createdAt.toUtc().year, 2026);
      expect(l.publishedAt, isNotNull);
      expect(l.moderatedAt, isNotNull);

      // Media: 2 foto + 1 planirovka.
      expect(l.media, hasLength(3));
      expect(l.photos, hasLength(2));
      expect(l.media.first.isCover, isTrue);
      expect(l.media.last.role, 'plan');
      expect(l.media.first.thumbUrl, isNull);
      expect(
        l.coverImageUrl,
        '/kadastr-3d-files/listings/media/3/aaaaaaaaaaaa.jpg',
      );
      // Galereyada faqat fotolar, muqova birinchi.
      expect(l.galleryUrls, hasLength(2));
      expect(l.galleryUrls.first, endsWith('aaaaaaaaaaaa.jpg'));
    });

    test('media yo‘q e‘lon: muqova null, galereya bo‘sh, null maydonlar', () {
      final l = BozorListing.fromJson(_decode(_pendingNoMediaJson));

      expect(l.status, ListingStatus.pending);
      expect(l.media, isEmpty);
      expect(l.coverImageUrl, isNull);
      expect(l.galleryUrls, isEmpty);

      expect(l.landmark, isNull);
      expect(l.floor, isNull);
      expect(l.latitude, isNull);
      expect(l.description, isNull);
      expect(l.contactEmail, isNull);
      expect(l.dailyAmount, isNull);
      expect(l.publishedAt, isNull);
      expect(l.moderatedAt, isNull);
      expect(l.regionLine, '');

      // Sotuvda ham, davri ko'rsatilmagan ijarada ham qo'shimcha yo'q.
      expect(l.pricePeriod, isNull);
      expect(l.priceCurrency, 'USD');
      expect(l.formattedDailyPrice(uz), isNull);
    });

    test('rad etilgan: sabab va holat egasiga ko‘rinadi', () {
      final l = BozorListing.fromJson(_decode(_rejectedJson));

      expect(l.status, ListingStatus.rejected);
      expect(l.rejectionReason, 'Rasmlar sifatsiz');
      expect(l.publishedAt, isNull);
      expect(l.moderatedAt, isNotNull);
      expect(l.status.label(uz), 'Rad etilgan');
    });

    test('noma‘lum status: ilova yiqilmaydi, xom kod saqlanadi', () {
      // Server kelajakda yangi holat qo'shsa (masalan `expired`) shunday keladi.
      final j = _decode(_pendingNoMediaJson)..['status'] = 'expired';
      final l = BozorListing.fromJson(j);

      expect(l.status, ListingStatus.unknown);
      expect(l.statusCode, 'expired');
      expect(l.status.label(uz), isNull);
    });

    test('bo‘sh javob ham parslanadi — hech qaysi maydon majburiy emas', () {
      // 200 lekin kesilgan javob (proksi, keshda eskirgan sxema) ilovani
      // yiqitmasin: bo'sh qiymatlar bilan ochiladi.
      final l = BozorListing.fromJson(const <String, dynamic>{});

      expect(l.id, 0);
      expect(l.status, ListingStatus.unknown);
      expect(l.priceAmount, 0);
      expect(l.priceCurrency, 'UZS');
      expect(l.media, isEmpty);
      expect(l.params, isEmpty);
      expect(l.roomsAreaLine(uz), isNull);
    });
  });

  group('Yorliqli getter‘lar', () {
    test('formattedPrice: mingliklar + valyuta + davr', () {
      final rent = BozorListing.fromJson(_decode(_approvedJson));
      expect(rent.formattedPrice(uz), '4 500 000 so\'m/oy');
      expect(rent.formattedDailyPrice(uz), '350 000 so\'m/kun');
      expect(rent.formattedPrice(const Locale('ru')), '4 500 000 сум/мес');

      final usd = BozorListing.fromJson(_decode(_pendingNoMediaJson));
      expect(usd.formattedPrice(uz), '1 200 \$');
    });

    test('roomsAreaLine: kasr maydon vergul bilan', () {
      final l = BozorListing.fromJson(_decode(_approvedJson));
      expect(l.roomsAreaLine(uz), '3 xona · 78,5 m²');
    });

    test('tur va bitim yorliqlari sehrgar kalitlaridan keladi', () {
      final l = BozorListing.fromJson(_decode(_approvedJson));
      expect(l.propertyTypeLabel(uz), isNot('apartment'));
      expect(l.dealTypeLabel(uz), isNot('rent'));
      // Notanish kod xom holda ko'rinadi — gap ko'zga tashlanadi.
      final j = _decode(_approvedJson)..['property_type'] = 'dacha';
      expect(BozorListing.fromJson(j).propertyTypeLabel(uz), 'dacha');
    });
  });

  group('BozorListingPage', () {
    // `GET /listings/` javobining aynan konverti.
    String envelope(String item, {int total = 1, int page = 1, int size = 20}) =>
        '{"items": [$item], "total": $total, "page": $page, "size": $size}';

    test('konvert: items + total + page + size', () {
      final p = BozorListingPage.fromJson(_decode(envelope(_approvedJson)));
      expect(p.items, hasLength(1));
      expect(p.items.first.id, 1);
      expect(p.total, 1);
      expect(p.page, 1);
      expect(p.size, 20);
      expect(p.hasMore, isFalse);
    });

    test('hasMore: kelgan qatorlar soni bo‘yicha', () {
      final more = BozorListingPage.fromJson(
        _decode(envelope(_approvedJson, total: 5, size: 1)),
      );
      expect(more.hasMore, isTrue);
      expect(more.nextPage, 2);

      final last = BozorListingPage.fromJson(
        _decode(envelope(_approvedJson, total: 3, page: 3, size: 1)),
      );
      expect(last.hasMore, isFalse);
    });
  });

  group('BozorApi lenta metodlari', () {
    test('listings(): filtrlar query‘ga tushadi, sahifalash page/size', () async {
      Uri? seen;
      final api = BozorApi(
        client: MockClient((req) async {
          seen = req.url;
          return http.Response(
            '{"items": [], "total": 0, "page": 2, "size": 30}',
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final page = await api.listings(
        dealType: 'rent',
        propertyType: 'apartment',
        regionId: 14,
        priceMin: 1000000,
        priceMax: 9000000,
        rooms: 3,
        areaMin: 40,
        search: '  chilonzor  ',
        page: 2,
        size: 30,
      );

      expect(page.items, isEmpty);
      expect(page.page, 2);
      expect(seen!.path, endsWith('/listings/'));
      expect(seen!.queryParameters, {
        'deal_type': 'rent',
        'property_type': 'apartment',
        'region_id': '14',
        'price_min': '1000000',
        'price_max': '9000000',
        'rooms': '3',
        'area_min': '40',
        'search': 'chilonzor',
        'page': '2',
        'size': '30',
      });
      // Berilmagan filtr query'ga UMUMAN tushmaydi (bo'sh qiymat 422 berardi).
      expect(seen!.queryParameters.containsKey('district_id'), isFalse);
      expect(seen!.queryParameters.containsKey('area_max'), isFalse);
    });

    test('myListings(): status alias‘i `status` nomi bilan ketadi', () async {
      Uri? seen;
      final api = BozorApi(
        client: MockClient((req) async {
          seen = req.url;
          return http.Response(
            '{"items": [], "total": 0, "page": 1, "size": 20}',
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await api.myListings(status: 'rejected');
      expect(seen!.path, endsWith('/listings/my'));
      expect(seen!.queryParameters, {
        'status': 'rejected',
        'page': '1',
        'size': '20',
      });

      // Holat berilmasa parametr BO'SH QIYMAT bilan ham ketmasligi kerak:
      // `?status=` FastAPI'da 422 berardi.
      await api.myListings();
      expect(seen!.queryParameters, {'page': '1', 'size': '20'});
      expect(seen!.query.contains('status'), isFalse);
    });

    test('listing(id): bitta e‘lon parslanadi', () async {
      final api = BozorApi(
        client: MockClient(
          (req) async => http.Response(
            _approvedJson,
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final l = await api.listing(1);
      expect(l.id, 1);
      expect(l.media, hasLength(3));
    });

    test('404 → BozorApiException, detail matni bilan', () async {
      final api = BozorApi(
        client: MockClient(
          (req) async => http.Response(
            jsonEncode({'detail': 'Eʼlon topilmadi'}),
            404,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await expectLater(
        api.listing(999),
        throwsA(
          isA<BozorApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Eʼlon topilmadi'),
        ),
      );
    });
  });
}
