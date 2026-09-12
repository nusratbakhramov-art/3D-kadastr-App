import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/core/api_config.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/feed/bozor_listing_detail_screen.dart';
import 'package:kadastr/features/market/widgets/listing_gallery_pager.dart';
import 'package:kadastr/features/market/widgets/listing_meta_pills.dart';
import 'package:kadastr/widgets/remote_image.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// E'lon detali ekrani.
///
/// Diqqat qilinadigan joy — PARAMETRLAR: `params` da KOD keladi
/// (`renovation: "euro"`), ekranda esa YORLIQ chiqishi kerak
/// (`/listings/options` dan). Ro'yxat kelmasa xom kod ekranga CHIQMASLIGI
/// kerak — pastdagi "yorliqlar ro'yxati kelmadi" testi aynan shuni qotiradi.
///
/// Yorliqlar bu yerda kalitning O'ZI bo'lib chiqadi (`bozor.detail.call`):
/// `tr()` bundle yuklanmagan holatda kalitni qaytaradi.
void main() {
  const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

  http.Response ok(Object body) =>
      http.Response(jsonEncode(body), 200, headers: jsonHeaders);

  /// Ro'yxatlar javobi — `params` dagi kodlarning yorliqlari.
  Map<String, dynamic> optionLists() => {
    'lists': {
      'rooms_count': [
        {'code': '3', 'label': '3'},
      ],
      'renovation': [
        {'code': 'euro', 'label': 'Yevro taʼmir'},
      ],
      'parking': [
        {'code': 'garage', 'label': 'Garaj'},
      ],
    },
  };

  Map<String, dynamic> listingJson({
    String status = 'approved',
    String? rejectionReason,
    List<Map<String, dynamic>>? media,
    Map<String, dynamic>? params,
    String propertyType = 'apartment',
  }) => {
    'id': 7,
    'status': status,
    'title': 'Chilonzorda 3 xonali kvartira',
    'deal_type': 'rent',
    'property_kind': 'residential',
    'property_type': propertyType,
    'region_name': 'Toshkent sh.',
    'district_name': 'Chilonzor tumani',
    'address': 'Chilonzor 9-kvartal, 12-uy',
    'floor': 3,
    'total_floors': 9,
    'rooms': 3,
    // Backend `Decimal` ni SATR qilib beradi — model shu holatni o'qiydi.
    'area_sqm': '78.50',
    'params':
        params ??
        {
          'rooms_count': '3',
          'total_area': 78.5,
          'renovation': 'euro',
          'gas': true,
          'parking': 'garage',
          'gsk_name': 'GSK-4',
        },
    'price_amount': '4500000.00',
    'price_currency': 'UZS',
    'price_period': 'month',
    'price_uzs': '4500000.00',
    'negotiable': true,
    'description': 'Yorugʼ kvartira, hammasi yaqin.',
    'contact_name': 'Ali',
    'contact_phone': '+998901234567',
    'contact_phones': ['+998901234567'],
    'rejection_reason': rejectionReason,
    'created_at': '2026-01-01T10:00:00Z',
    'media':
        media ??
        [
          {
            'id': 1,
            'role': 'photo',
            'url': 'https://example.test/a.jpg',
            'is_cover': true,
            'sort_order': 0,
          },
        ],
  };

  /// Soxta klient. `/listings/options` va `/listings/{id}` bir xil prefiksda
  /// bo'lgani uchun tartib muhim — `options` OLDIN tekshiriladi.
  BozorApi apiReturning({
    Map<String, dynamic>? listing,
    int listingStatus = 200,
    int optionsStatus = 200,
    Map<String, dynamic>? options,
    Duration delay = Duration.zero,
  }) {
    return BozorApi(
      client: MockClient((req) async {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (req.url.path.endsWith('/listings/options')) {
          if (optionsStatus != 200) {
            return http.Response('boom', optionsStatus);
          }
          return ok(options ?? optionLists());
        }
        if (listingStatus != 200) {
          return http.Response(
            jsonEncode({'detail': 'Eʼlon topilmadi'}),
            listingStatus,
            headers: jsonHeaders,
          );
        }
        return ok(listing ?? listingJson());
      }),
    );
  }

  /// Ekran BALAND oynada chiziladi.
  ///
  /// Kerak, chunki mazmun `ListView` da: sukut bo'yicha 800px oynada
  /// parametrlar va kontakt bloklari ekrandan pastda qoladi va `ListView`
  /// ularni UMUMAN qurmaydi — `find` esa qurilmagan widget'ni ko'rmaydi.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  /// Ekranni ochadi va javoblar kelib bo'lishini kutadi.
  ///
  /// `pumpAndSettle` ISHLATILMAYDI: rasm joyidagi shimmer va spinner
  /// cheksiz aylanadi, ya'ni "settle" holati hech qachon kelmaydi.
  Future<void> open(WidgetTester tester, BozorApi api) async {
    tallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(home: BozorListingDetailScreen(listingId: 7, api: api)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('yuklanish — spinner, keyin e\'lon', (tester) async {
    final api = apiReturning(delay: const Duration(milliseconds: 300));
    await tester.pumpWidget(
      MaterialApp(home: BozorListingDetailScreen(listingId: 7, api: api)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsNothing);

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
  });

  testWidgets('muvaffaqiyat — galereya, narx va parametr YORLIQLARI', (
    tester,
  ) async {
    await open(tester, apiReturning());

    expect(find.byType(ListingGalleryPager), findsOneWidget);
    expect(
      tester.widget<ListingGalleryPager>(find.byType(ListingGalleryPager)).images,
      ['https://example.test/a.jpg'],
    );

    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
    expect(find.text('Yorugʼ kvartira, hammasi yaqin.'), findsOneWidget);
    // Narx satri model formatlaydi: davri va valyuta yorlig'i bilan.
    expect(
      find.text(
        '4 500 000 bozor.listing.currency.uzsbozor.listing.period.month',
      ),
      findsOneWidget,
    );

    // Kod → yorliq.
    expect(find.text('Yevro taʼmir'), findsOneWidget);
    expect(find.text('Garaj'), findsOneWidget);
    // Xom kod ekranda YO'Q.
    expect(find.text('euro'), findsNothing);
    expect(find.text('garage'), findsNothing);
    // Yorliq ustuni — parametr kalitlari.
    expect(find.text('bozor.param.renovation'), findsOneWidget);
    expect(find.text('bozor.param.parking'), findsOneWidget);
    // Toggle → "Bor"/"Yo'q" kaliti, matnli parametr esa o'zi.
    expect(find.text('bozor.detail.yes'), findsOneWidget);
    expect(find.text('GSK-4'), findsOneWidget);

    // Manzil va kontakt.
    expect(find.text('Chilonzor 9-kvartal, 12-uy'), findsOneWidget);
    expect(find.text('3 / 9'), findsOneWidget);
    expect(find.text('+998901234567'), findsOneWidget);
    expect(find.text('bozor.detail.call'), findsOneWidget);
  });

  testWidgets('yorliqlar ro\'yxati kelmadi — xom kod chiqmaydi', (
    tester,
  ) async {
    await open(tester, apiReturning(optionsStatus: 500));

    expect(tester.takeException(), isNull);
    // Kod bo'yicha qatorlar umuman chizilmaydi.
    expect(find.text('euro'), findsNothing);
    expect(find.text('garage'), findsNothing);
    expect(find.text('Yevro taʼmir'), findsNothing);
    expect(find.text('bozor.param.renovation'), findsNothing);
    // Sonli/matnli parametrlar esa joyida — ekran bo'shab qolmaydi.
    expect(find.text('GSK-4'), findsOneWidget);
    expect(find.text('bozor.param.gsk_name'), findsOneWidget);
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
  });

  testWidgets('rasm bosilsa to\'liq ekran (zoom) galereyasi ochiladi', (
    tester,
  ) async {
    await open(tester, apiReturning());

    // `PageView` ning o'z ishorachilari ham bor — rasmning O'ZIDAGISI
    // (`RemoteImage` ustidagi) kerak.
    await tester.tap(
      find.ancestor(
        of: find.byType(RemoteImage),
        matching: find.byType(GestureDetector),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // `photo_view` galereyasi — zoom shu yerda.
    expect(find.byType(PhotoViewGallery), findsOneWidget);
  });

  testWidgets('nisbiy rasm havolasi absolyutga aylanadi', (tester) async {
    // S3 sozlanmagan muhitda backend `/kadastr-3d-files/...` qaytaradi —
    // `Image.network` bunday manzilni ocholmaydi.
    await open(
      tester,
      apiReturning(
        listing: listingJson(
          media: const [
            {
              'id': 1,
              'role': 'photo',
              'url': '/kadastr-3d-files/listings/media/3/a.jpg',
              'is_cover': true,
              'sort_order': 0,
            },
          ],
        ),
      ),
    );

    expect(
      tester
          .widget<ListingGalleryPager>(find.byType(ListingGalleryPager))
          .images,
      [ApiConfig.resolveUrl('/kadastr-3d-files/listings/media/3/a.jpg')],
    );
  });

  testWidgets('rasm yo\'q — placeholder, yiqilmaydi', (tester) async {
    await open(tester, apiReturning(listing: listingJson(media: const [])));

    expect(tester.takeException(), isNull);
    expect(find.byType(ListingGalleryPager), findsOneWidget);
    expect(
      tester.widget<ListingGalleryPager>(find.byType(ListingGalleryPager)).images,
      isEmpty,
    );
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
  });

  testWidgets('rejected — sabab ko\'rinadi', (tester) async {
    await open(
      tester,
      apiReturning(
        listing: listingJson(
          status: 'rejected',
          rejectionReason: 'Rasm sifati past',
        ),
      ),
    );

    expect(find.text('bozor.detail.rejected_title'), findsOneWidget);
    expect(find.text('bozor.detail.rejection_reason'), findsOneWidget);
    expect(find.text('Rasm sifati past'), findsOneWidget);
  });

  testWidgets('pending — egasiga izoh, rad etish bloki yo\'q', (tester) async {
    await open(tester, apiReturning(listing: listingJson(status: 'pending')));

    expect(find.text('listings.status.moderation'), findsOneWidget);
    expect(find.text('bozor.detail.pending_note'), findsOneWidget);
    expect(find.text('bozor.detail.rejected_title'), findsNothing);
  });

  testWidgets('xato — qayta urinish tugmasi ishlaydi', (tester) async {
    var calls = 0;
    final api = BozorApi(
      client: MockClient((req) async {
        if (req.url.path.endsWith('/listings/options')) {
          return ok(optionLists());
        }
        calls++;
        // Birinchi so'rov yiqiladi, ikkinchisi — muvaffaqiyat.
        if (calls == 1) return http.Response('boom', 500);
        return ok(listingJson());
      }),
    );

    await open(tester, api);
    expect(find.text('bozor.detail.load_failed'), findsOneWidget);
    expect(find.text('common.retry'), findsOneWidget);

    await tester.tap(find.text('common.retry'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('bozor.detail.load_failed'), findsNothing);
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
  });

  testWidgets('404 — "topilmadi", qayta urinish YO\'Q', (tester) async {
    await open(tester, apiReturning(listingStatus: 404));

    expect(find.text('bozor.detail.not_found'), findsOneWidget);
    // Qayta so'rov ham xuddi shu 404 ni beradi — tugma ko'rsatilmaydi.
    expect(find.text('common.retry'), findsNothing);
    expect(find.text('common.close'), findsOneWidget);
  });

  // ── Yorliq so'rovi ekranni GAROVGA OLMAYDI ─────────────────────────────────
  // Eng qimmat xato shu yerda edi: `/listings/options` `_load` ichida
  // `await` qilinardi va u osilib qolsa ekran spinner'da qotardi, holbuki
  // e'lon ma'lumoti allaqachon qo'lda.

  testWidgets('options OSILIB qolsa — e\'lon SHUNDA HAM ko\'rinadi', (
    tester,
  ) async {
    // Ro'yxatlar javobi HECH QACHON kelmaydi (tarmoq "o'lik" ulanish).
    final api = BozorApi(
      client: MockClient((req) {
        if (req.url.path.endsWith('/listings/options')) {
          return Completer<http.Response>().future;
        }
        return Future.value(ok(listingJson()));
      }),
    );

    await open(tester, api);

    // Spinner YO'Q, e'lon esa joyida.
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
    expect(find.text('+998901234567'), findsOneWidget);
    // Sonli/matnli parametrlar tarmoqqa bog'liq emas.
    expect(find.text('GSK-4'), findsOneWidget);
    // Yorliqsiz select qatorlari chizilmaydi — xom kod ham chiqmaydi.
    expect(find.text('euro'), findsNothing);
    expect(find.text('Yevro taʼmir'), findsNothing);

    // Klientdagi 20s timeout taymerini "bo'shatamiz" (aks holda test
    // oxirida osilib turgan taymerdan yiqiladi) — ekran shundan keyin ham
    // e'lonni ko'rsatishda davom etadi.
    await tester.pump(const Duration(seconds: 21));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
  });

  testWidgets('options 500 — so\'rov BITTA, maydon boshiga takrorlanmaydi', (
    tester,
  ) async {
    var optionsCalls = 0;
    final api = BozorApi(
      client: MockClient((req) async {
        if (req.url.path.endsWith('/listings/options')) {
          optionsCalls++;
          return http.Response('boom', 500);
        }
        return ok(listingJson());
      }),
    );

    await open(tester, api);

    // E'londa 4 ta select/multiSelect maydon bor (`rooms_count`,
    // `renovation`, `parking` + garaj bloki). Ilgari har biri ALOHIDA
    // so'rov yuborardi, chunki `ApiParamOptions` xatoni keshlamaydi.
    expect(optionsCalls, 1);
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
  });

  testWidgets('yorliqlar KECHIKSA — e\'lon oldin, yorliq keyin', (
    tester,
  ) async {
    final api = BozorApi(
      client: MockClient((req) async {
        if (req.url.path.endsWith('/listings/options')) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          return ok(optionLists());
        }
        return ok(listingJson());
      }),
    );

    tallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(home: BozorListingDetailScreen(listingId: 7, api: api)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // E'lon KO'RINDI, yorliq esa hali yo'lda.
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
    expect(find.text('Yevro taʼmir'), findsNothing);

    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Yorliq kelgach qator O'ZI qo'shiladi.
    expect(find.text('Yevro taʼmir'), findsOneWidget);
    expect(find.text('Garaj'), findsOneWidget);
  });

  testWidgets('til almashsa parametr yorliqlari YANGI tilda qayta olinadi', (
    tester,
  ) async {
    final locales = <String>[];
    final api = BozorApi(
      client: MockClient((req) async {
        if (req.url.path.endsWith('/listings/options')) {
          final locale = req.url.queryParameters['locale'] ?? '';
          locales.add(locale);
          return ok({
            'lists': {
              'renovation': [
                {
                  'code': 'euro',
                  'label': locale == 'ru' ? 'Евроремонт' : 'Yevro taʼmir',
                },
              ],
            },
          });
        }
        return ok(listingJson(params: const {'renovation': 'euro'}));
      }),
    );

    Widget app(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('uz'), Locale('ru')],
      home: BozorListingDetailScreen(listingId: 7, api: api),
    );

    tallSurface(tester);
    await tester.pumpWidget(app(const Locale('uz')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Yevro taʼmir'), findsOneWidget);

    // Til almashdi — ekranning qolgan matni `tr()` bilan darhol o'zgaradi,
    // parametr bloki ham ORQADA QOLMASLIGI kerak.
    await tester.pumpWidget(app(const Locale('ru')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(locales, ['uz', 'ru']);
    expect(find.text('Евроремонт'), findsOneWidget);
    expect(find.text('Yevro taʼmir'), findsNothing);
  });

  // ── Yarim ma'lumot ko'rsatmaslik ───────────────────────────────────────────

  testWidgets('multiSelect — kodlardan biri topilmasa qator CHIZILMAYDI', (
    tester,
  ) async {
    await open(
      tester,
      apiReturning(
        listing: listingJson(
          params: const {'security': ['guard', 'cctv']},
        ),
        // Ro'yxatda faqat `guard` bor: `cctv` yo'q (server yangi kod
        // qo'shgan, ilova esa eski ro'yxatni ko'rgan).
        options: const {
          'lists': {
            'security': [
              {'code': 'guard', 'label': 'Qorovul'},
            ],
          },
        },
      ),
    );

    // QISMIY ro'yxat eng yomon variant: "Qorovul" yolg'iz chiqsa
    // foydalanuvchi e'londa bittagina xavfsizlik vositasi bor deb o'ylaydi.
    expect(find.text('Qorovul'), findsNothing);
    expect(find.text('bozor.param.security'), findsNothing);
    expect(find.text('cctv'), findsNothing);
    // Ekranning qolgani ishlashda davom etadi.
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
  });

  testWidgets('multiSelect — hamma kod topilsa hammasi ko\'rinadi', (
    tester,
  ) async {
    await open(
      tester,
      apiReturning(
        listing: listingJson(
          params: const {'security': ['guard', 'cctv']},
        ),
        options: const {
          'lists': {
            'security': [
              {'code': 'guard', 'label': 'Qorovul'},
              {'code': 'cctv', 'label': 'Videokuzatuv'},
            ],
          },
        },
      ),
    );

    expect(find.text('Qorovul, Videokuzatuv'), findsOneWidget);
  });

  testWidgets('notanish mulk turi — nishonda XOM KOD yo\'q', (tester) async {
    await open(
      tester,
      apiReturning(listing: listingJson(propertyType: 'dacha')),
    );

    // Server yangi tur qo'shsa nishon UMUMAN chizilmaydi.
    expect(find.text('dacha'), findsNothing);
    final pills = tester
        .widgetList<ListingMetaPill>(find.byType(ListingMetaPill))
        .map((p) => p.text)
        .toList();
    expect(pills, isNot(contains('dacha')));
    // Qolgan nishonlar joyida.
    expect(pills, contains('Toshkent sh., Chilonzor tumani'));
    expect(find.text('Chilonzorda 3 xonali kvartira'), findsOneWidget);
  });

  testWidgets('toggle — satr "true"/"0" to\'g\'ri, tushunarsizda qator yo\'q', (
    tester,
  ) async {
    // Backend `params` ni tipsiz `dict` saqlaydi: bool satr bo'lib ham
    // keladi. Ilgari `raw == true` qat'iy solishtirish "true" ni "Yo'q" deb
    // ko'rsatardi — jimgina NOTO'G'RI ma'lumot.
    await open(
      tester,
      apiReturning(
        listing: listingJson(
          params: const {
            'gas': 'true',
            'freight_elevator': '0',
            'electricity': 'ha',
          },
        ),
      ),
    );

    expect(find.text('bozor.param.gas'), findsOneWidget);
    expect(find.text('bozor.detail.yes'), findsOneWidget);
    expect(find.text('bozor.param.freight_elevator'), findsOneWidget);
    expect(find.text('bozor.detail.no'), findsOneWidget);
    // Tushunarsiz qiymat — qator umuman chizilmaydi ("Yo'q" deb yozib
    // qo'yish yolg'on bo'lardi).
    expect(find.text('bozor.param.electricity'), findsNothing);
    expect(find.text('ha'), findsNothing);
  });

  testWidgets('archived — egasiga arxiv banneri', (tester) async {
    await open(tester, apiReturning(listing: listingJson(status: 'archived')));

    expect(find.text('listings.status.archived'), findsOneWidget);
    expect(find.text('bozor.detail.archived_note'), findsOneWidget);
    // Arxiv rad etish ham, moderatsiya ham emas.
    expect(find.text('bozor.detail.rejected_title'), findsNothing);
    expect(find.text('bozor.detail.pending_note'), findsNothing);
  });

  testWidgets('maydon nishoni model formatlovchisi bilan bir xil', (
    tester,
  ) async {
    // `_formatNumber` nusxasi o'chirildi: ekran ham modelning
    // `formatBozorAmount` ini ishlatadi (ikkisi ajralib ketmasin).
    await open(tester, apiReturning());

    final pills = tester
        .widgetList<ListingMetaPill>(find.byType(ListingMetaPill))
        .map((p) => p.text)
        .toList();
    expect(pills, contains('78,5 bozor.unit.m²'));
  });

  group('tahrirlash tugmasi — HOLATGA qarab', () {
    /// ⚠️ NEGA BU TEST BOR. `pending` (moderatsiyadagi) e'lonni tahrirlash
    /// 2026-09-12 da ATAYLAB yopildi: `draftFromListing` mavjud fayllarni
    /// faqat `existingMedia` ga soladi, sehrgar esa uni o'qimaydi — ya'ni
    /// tahrirlashda 360/foto/planirovka qatorlari BO'SH chiqadi va yangi
    /// xonani eskisiga tur bilan bog'lab bo'lmaydi.
    ///
    /// `rejected` ATAYLAB qoldirilgan: usiz rad etilgan e'lon abadiy o'lik
    /// qolardi. Shartni kimdir "tartibga solib" qaytarib qo'ymasin.
    ///
    /// Tugma IKONKA bo'yicha qidiriladi: bu test faylida tarjimalar
    /// yuklanmaydi, ya'ni yorliq xom kalit bo'lib chiqadi.
    Future<void> openOwned(WidgetTester tester, String status) async {
      tallSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: BozorListingDetailScreen(
            listingId: 7,
            api: apiReturning(listing: listingJson(status: status)),
            isOwner: true,
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('MODERATSIYADAGI (pending) e\'londa tugma YO\'Q',
        (tester) async {
      await openOwned(tester, 'pending');
      expect(find.byIcon(Icons.edit_outlined), findsNothing,
          reason: 'moderatsiyadagi e\'lon tahrirlanmasligi kerak');
      // Arxivlash QOLADI — u boshqa masala.
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    testWidgets('RAD ETILGAN (rejected) e\'londa tugma BOR', (tester) async {
      await openOwned(tester, 'rejected');
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget,
          reason: 'rad etilgan e\'lonni tuzatib bo\'lmasa u o\'lik qoladi');
    });
  });
}
