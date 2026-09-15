import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadastr/features/bozor/data/bozor_api.dart';
import 'package:kadastr/features/bozor/feed/bozor_draft_card.dart';
import 'package:kadastr/features/bozor/feed/bozor_home_screen.dart';
import 'package:kadastr/features/bozor/feed/bozor_listing_card.dart';

/// «Bozor» ekrani — ikki tab.
///
/// Kalitlar tarjima qilinmagan holda tekshiriladi (`tr` topmasa kalitning
/// O'ZINI qaytaradi) — bu ataylab: test matn o'zgarishiga emas, TUZILISHGA
/// bog'lanadi.

String _listingJson(int id, {String status = 'approved', String? reason}) => '''
{
  "id": $id, "status": "$status", "deal_type": "rent",
  "property_kind": "residential", "property_type": "apartment",
  "title": "E'lon $id", "address": "Chilonzor 5",
  "region_name": "Toshkent", "district_name": "Chilonzor",
  "rooms": 3, "area_sqm": "72.50",
  "price_amount": "4500000.00", "price_currency": "UZS",
  "price_period": "month", "negotiable": true,
  "contact_name": "Ali", "contact_phone": "901234567",
  "contact_phones": ["901234567"], "contact_phone_verified": false,
  "tier": "standard", "top_rank": 0,
  ${reason == null ? '' : '"rejection_reason": "$reason",'}
  "params": {}, "media": [], "created_at": "2026-09-10T10:00:00Z"
}''';

String _page(List<String> items) =>
    '{"items": [${items.join(',')}], "total": ${items.length}, "page": 1, "size": 20}';

const _draftJson = '''
{"items": [{
  "id": 5, "current_step": "price", "payload": {"title": "Qoralama e'lon"},
  "title": "Qoralama e'lon", "deal_type": "rent", "property_type": "apartment",
  "address": "Yunusobod 4", "created_at": "2026-09-10T09:00:00Z",
  "updated_at": "2026-09-10T09:30:00Z"
}], "total": 1, "limit": 20}''';

/// Yo'l bo'yicha javob beradigan soxta klient. `null` javob → 500.
BozorApi _api({
  String? feed,
  String? mine,
  String? drafts,
  int mineStatus = 200,
  int draftsStatus = 200,
}) {
  final client = MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/listings/drafts')) {
      return http.Response.bytes(
        utf8.encode(drafts ?? '{"detail":"xato"}'),
        draftsStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    if (p.endsWith('/listings/my')) {
      return http.Response.bytes(
        utf8.encode(mine ?? '{"detail":"xato"}'),
        mineStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    if (p.endsWith('/listings/') || p.endsWith('/listings')) {
      return http.Response.bytes(
        utf8.encode(feed ?? '{"detail":"xato"}'),
        feed == null ? 500 : 200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 200);
  });
  return BozorApi(client: client);
}

Future<void> _pump(WidgetTester tester, BozorApi api) async {
  await tester.pumpWidget(MaterialApp(home: BozorHomeScreen(api: api)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ikkita tab chiziladi va «E‘lon qo‘shish» tugmasi bor', (
    tester,
  ) async {
    await _pump(tester, _api(feed: _page(const []), mine: _page(const []), drafts: '{"items":[],"total":0,"limit":20}'));
    expect(find.text('bozor.feed.tab_all'), findsOneWidget);
    expect(find.text('bozor.feed.tab_mine'), findsOneWidget);
    expect(find.text('bozor.feed.add'), findsOneWidget);
  });

  testWidgets('lenta: e‘lonlar karta bo‘lib chiqadi', (tester) async {
    await _pump(
      tester,
      _api(
        feed: _page([_listingJson(1), _listingJson(2)]),
        mine: _page(const []),
        drafts: '{"items":[],"total":0,"limit":20}',
      ),
    );
    // `ListView` faqat ko'rinadigan elementni quradi — ikkinchisiga
    // skroll qilib yetamiz.
    expect(find.text("E'lon 1"), findsOneWidget);
    expect(find.byType(BozorListingCard), findsWidgets);
    // `scrollUntilVisible` ISHLATILMAYDI: ekranda bir nechta `Scrollable`
    // bor (ikki tab + `TabBarView`) va u "Too many elements" beradi.
    expect(find.text("E'lon 2"), findsNothing);
    await tester.drag(
      find.byType(BozorListingCard).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.text("E'lon 2"), findsOneWidget);
  });

  testWidgets('lenta bo‘sh — bo‘shlik holati', (tester) async {
    await _pump(tester, _api(feed: _page(const []), mine: _page(const []), drafts: '{"items":[],"total":0,"limit":20}'));
    expect(find.text('bozor.feed.empty_all'), findsOneWidget);
  });

  testWidgets('lenta yiqildi — xato va «qayta urinish»', (tester) async {
    await _pump(tester, _api(mine: _page(const []), drafts: '{"items":[],"total":0,"limit":20}'));
    expect(find.text('bozor.feed.load_failed'), findsOneWidget);
    expect(find.text('bozor.feed.retry'), findsOneWidget);
  });

  group('«Mening e‘lonlarim»', () {
    testWidgets('403 — tizimga kirish taklifi (xato emas)', (tester) async {
      // Sarlavha umuman yo'q bo'lsa backend 403 qaytaradi.
      await _pump(
        tester,
        _api(feed: _page(const []), mineStatus: 403, draftsStatus: 403),
      );
      await tester.tap(find.text('bozor.feed.tab_mine'));
      await tester.pumpAndSettle();
      expect(find.text('bozor.feed.login_required'), findsOneWidget);
      // Bu XATO emas — "qayta urinish" ko'rsatilmasin.
      expect(find.text('bozor.feed.retry'), findsNothing);
    });

    testWidgets('qoralama e‘londan TEPADA va nishoni bor', (tester) async {
      await _pump(
        tester,
        _api(
          feed: _page(const []),
          mine: _page([_listingJson(9)]),
          drafts: _draftJson,
        ),
      );
      await tester.tap(find.text('bozor.feed.tab_mine'));
      await tester.pumpAndSettle();

      expect(find.byType(BozorDraftCard), findsOneWidget);
      expect(find.text('bozor.draft.badge'), findsOneWidget);
      expect(find.text("Qoralama e'lon"), findsOneWidget);

      // Tugatilmagan ish yuqorida turishi kerak: u foydalanuvchidan harakat
      // kutadi, tasdiqlangan e'lon esa allaqachon ishlab turadi.
      final draftY = tester.getTopLeft(find.byType(BozorDraftCard)).dy;
      final cardY = tester.getTopLeft(find.byType(BozorListingCard)).dy;
      expect(draftY, lessThan(cardY));
    });

    testWidgets('holat nishoni FAQAT o‘z e‘lonlarimda ko‘rinadi', (
      tester,
    ) async {
      await _pump(
        tester,
        _api(
          feed: _page([_listingJson(1)]),
          mine: _page([_listingJson(2, status: 'pending')]),
          drafts: '{"items":[],"total":0,"limit":20}',
        ),
      );
      // Lentada hammasi `approved` — nishon shovqin bo'lardi.
      expect(find.text('listings.status.approved'), findsNothing);
      await tester.tap(find.text('bozor.feed.tab_mine'));
      await tester.pumpAndSettle();
      expect(find.text('listings.status.moderation'), findsOneWidget);
    });

    testWidgets('rad etilgan e‘londa SABAB kartada ko‘rinadi', (tester) async {
      await _pump(
        tester,
        _api(
          feed: _page(const []),
          mine: _page([
            _listingJson(3, status: 'rejected', reason: 'Rasm sifati past'),
          ]),
          drafts: '{"items":[],"total":0,"limit":20}',
        ),
      );
      await tester.tap(find.text('bozor.feed.tab_mine'));
      await tester.pumpAndSettle();
      expect(find.text('listings.status.rejected'), findsOneWidget);
      // Egasi detalga kirmasdan nima tuzatishni bilishi kerak.
      expect(find.text('Rasm sifati past'), findsOneWidget);
    });

    testWidgets('bittasi yiqilsa ikkinchisi baribir ko‘rsatiladi', (
      tester,
    ) async {
      // `/my` 500, qoralamalar keldi → qoralama ko'rinadi, xato ekrani YO'Q.
      await _pump(
        tester,
        _api(feed: _page(const []), mineStatus: 500, drafts: _draftJson),
      );
      await tester.tap(find.text('bozor.feed.tab_mine'));
      await tester.pumpAndSettle();
      expect(find.byType(BozorDraftCard), findsOneWidget);
      expect(find.text('bozor.feed.load_failed'), findsNothing);
    });

    testWidgets('IKKALASI yiqilsa xato holati', (tester) async {
      await _pump(
        tester,
        _api(feed: _page(const []), mineStatus: 500, draftsStatus: 500),
      );
      await tester.tap(find.text('bozor.feed.tab_mine'));
      await tester.pumpAndSettle();
      expect(find.text('bozor.feed.load_failed'), findsOneWidget);
      expect(find.text('bozor.feed.retry'), findsOneWidget);
    });

    testWidgets('qoralamani o‘chirish TASDIQ so‘raydi', (tester) async {
      await _pump(
        tester,
        _api(feed: _page(const []), mine: _page(const []), drafts: _draftJson),
      );
      await tester.tap(find.text('bozor.feed.tab_mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('bozor.draft.delete_title'), findsOneWidget);
      expect(find.text('common.cancel'), findsOneWidget);
      // Bekor qilinsa qoralama JOYIDA qoladi.
      await tester.tap(find.text('common.cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(BozorDraftCard), findsOneWidget);
    });
  });
}
