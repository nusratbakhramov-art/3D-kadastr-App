/// "Bozor AI" e'lonlarining backend klienti.
///
/// [AuthHttpClient] tokenni o'zi qo'shadi va 401 da yangilaydi.
///
/// Bu yerda YORLIQ emas, KOD yuriydi: `select`/`multiSelect` qiymatlari
/// `listing.option.*` kodlari (`garage`, `business_center`…), yorliqlar esa
/// `/listings/options` dan tilга qarab keladi. Shu sababli til almashganda
/// shartli maydonlar ishlashda davom etadi.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api_config.dart';
import '../../auth/auth_http_client.dart';
import '../models/bozor_listing.dart';

/// Kod + shu tildagi yorliq.
class ListingOption {
  const ListingOption({required this.code, required this.label});

  final String code;
  final String label;

  factory ListingOption.fromJson(Map<String, dynamic> j) => ListingOption(
    code: (j['code'] ?? '').toString(),
    label: (j['label'] ?? j['code'] ?? '').toString(),
  );

  @override
  bool operator ==(Object other) =>
      other is ListingOption && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

class BozorApiException implements Exception {
  BozorApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'BozorApiException($statusCode): $message';
}

class BozorApi {
  BozorApi({http.Client? client}) : _client = client ?? AuthHttpClient();

  final http.Client _client;

  void dispose() => _client.close();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  // ── Ma'lumotnomalar ───────────────────────────────────────────────────────
  /// 1-qadam ro'yxatlari + "Top" tarifi yoqilganmi.
  Future<ListingReference> reference(String locale) async {
    final body = await _getJson(_uri('/listings/reference', {'locale': locale}));
    return ListingReference.fromJson(body);
  }

  /// 3-qadamning barcha tanlov ro'yxatlari — BITTA so'rovda.
  Future<Map<String, List<ListingOption>>> options(String locale) async {
    final body = await _getJson(_uri('/listings/options', {'locale': locale}));
    final lists = (body['lists'] as Map?)?.cast<String, dynamic>() ?? const {};
    return {
      for (final e in lists.entries)
        e.key: [
          for (final o in (e.value as List? ?? const []))
            if (o is Map) ListingOption.fromJson(o.cast<String, dynamic>()),
        ],
    };
  }

  /// 3-qadam SXEMASI — qaysi turda qanday maydonlar bor.
  ///
  /// Til berilmaydi: javobda yorliq yo'q, faqat kalitlar. Matnlar
  /// `app_translations` dan `bozor.param.<key>` bo'yicha olinadi.
  Future<Map<String, dynamic>> paramSchema() =>
      _getJson(_uri('/listings/schema', const {}));

  /// Viloyat → tuman daraxti. `marketplace` moduliniki — e'lonlar uchun ham
  /// SHU ro'yxat ishlatiladi, ikkinchisini yaratmaymiz.
  Future<List<RegionNode>> regionsTree() async {
    final res = await _client
        .get(_uri('/marketplace/regions/tree'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw BozorApiException('HTTP ${res.statusCode}', statusCode: res.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final list = decoded is List ? decoded : (decoded['items'] as List? ?? const []);
    return [
      for (final r in list)
        if (r is Map) RegionNode.fromJson(r.cast<String, dynamic>()),
    ];
  }

  // ── Media ─────────────────────────────────────────────────────────────────
  /// Rasmlarni e'londan OLDIN yuklaydi. Qaytgan `key` larni yaratishga
  /// beramiz; `url` esa darhol ko'rsatish uchun.
  Future<List<UploadedMedia>> uploadMedia({
    required String role,
    required List<String> paths,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/listings/media'))
      ..fields['role'] = role;
    for (final p in paths) {
      req.files.add(await http.MultipartFile.fromPath('files', p));
    }
    final streamed = await _client.send(req).timeout(const Duration(minutes: 5));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 201) {
      throw BozorApiException(_errorOf(res), statusCode: res.statusCode);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final f in (body['files'] as List? ?? const []))
        if (f is Map) UploadedMedia.fromJson(f.cast<String, dynamic>()),
    ];
  }

  // ── E'lon ─────────────────────────────────────────────────────────────────
  /// E'lon yaratadi. Javobda `status` HAR DOIM `pending` — moderatsiyadan
  /// keyin ommaviy bo'ladi.
  Future<Map<String, dynamic>> createListing(Map<String, dynamic> payload) async {
    final res = await _client
        .post(
          _uri('/listings/'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 40));
    if (res.statusCode != 201) {
      throw BozorApiException(_errorOf(res), statusCode: res.statusCode);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// Ommaviy lenta — faqat `approved` e'lonlar, anonim ham ko'radi.
  ///
  /// Sahifalash `page`/`size` (cursor YO'Q). `size` ning yuqori chegarasi
  /// backendda **50** — kattasini yuborsak 422 qaytadi.
  /// Narx filtri NORMALLASHTIRILGAN `price_uzs` bo'yicha, ya'ni chegaralar
  /// har doim SO'MDA yuboriladi (dollarlik e'lon ham shunga tushadi).
  Future<BozorListingPage> listings({
    String? dealType,
    String? propertyType,
    int? regionId,
    int? districtId,
    num? priceMin,
    num? priceMax,
    int? rooms,
    num? areaMin,
    num? areaMax,
    String? search,
    int page = 1,
    int size = 20,
  }) async {
    final body = await _getJson(
      _uri('/listings/', {
        'deal_type': ?dealType,
        'property_type': ?propertyType,
        if (regionId != null) 'region_id': '$regionId',
        if (districtId != null) 'district_id': '$districtId',
        if (priceMin != null) 'price_min': '$priceMin',
        if (priceMax != null) 'price_max': '$priceMax',
        if (rooms != null) 'rooms': '$rooms',
        if (areaMin != null) 'area_min': '$areaMin',
        if (areaMax != null) 'area_max': '$areaMax',
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'page': '$page',
        'size': '$size',
      }),
    );
    return BozorListingPage.fromJson(body);
  }

  /// "Mening e'lonlarim" — moderatsiyadagi va rad etilganlari BILAN.
  /// Token SHART (`AuthHttpClient` qo'shadi); mehmon 401 oladi.
  ///
  /// [status] — `pending` | `approved` | `rejected` | `archived`; `null` bo'lsa
  /// hammasi. `size` chegarasi bu yerda **100** (lentadagidan boshqa).
  Future<BozorListingPage> myListings({
    String? status,
    int page = 1,
    int size = 20,
  }) async {
    final body = await _getJson(
      _uri('/listings/my', {
        'status': ?status,
        'page': '$page',
        'size': '$size',
      }),
    );
    return BozorListingPage.fromJson(body);
  }

  /// Bitta e'lon. Tasdiqlanmaganini FAQAT egasi ko'radi — begonaga 404
  /// ("Eʼlon topilmadi") keladi, ya'ni "yo'q" va "hali tasdiqlanmagan"
  /// klientda ajratilmaydi (ataylab: mavjudligi oshkor bo'lmasin).
  Future<BozorListing> listing(int id) async {
    final body = await _getJson(_uri('/listings/$id'));
    return BozorListing.fromJson(body);
  }

  /// Mavjud e'lonni tahrirlaydi. Faqat `pending`/`rejected` holatida
  /// mumkin; `rejected` e'lon tahrirlangach server uni QAYTA `pending` ga
  /// o'tkazadi va rad etish sababini tozalaydi.
  ///
  /// ⚠️ Berilgan bo'limlar ALMASHTIRILADI, berilmagani tegilmaydi. Ayniqsa
  /// `description.media`: uni umuman yubormaslik = "rasmlarga tegmang",
  /// bo'sh ro'yxat yuborish = "hammasini olib tashla".
  Future<Map<String, dynamic>> updateListing(
    int id,
    Map<String, dynamic> payload,
  ) async => _sendJson(
    'PATCH',
    _uri('/listings/$id'),
    payload,
    expect: 200,
    timeout: const Duration(seconds: 40),
  );

  /// E'lonni arxivlaydi — lentadan yo'qoladi. `archived` OXIRGI holat:
  /// serverda undan qaytish o'tishi yo'q, ya'ni bu qaytarib bo'lmaydigan.
  Future<Map<String, dynamic>> archiveListing(int id) async => _sendJson(
    'POST',
    _uri('/listings/$id/archive'),
    null,
    expect: 200,
  );

  // ── Qoralamalar ───────────────────────────────────────────────────────────
  // Hammasi tizimga kirishni talab qiladi. DIQQAT: `Authorization` sarlavhasi
  // UMUMAN bo'lmasa backend **403** qaytaradi (`HTTPBearer(auto_error=True)`),
  // 401 esa token YUBORILGAN, lekin yaroqsiz bo'lganda keladi — xato ishlovi
  // ikkalasini ham "tizimga kirmagan" deb qarashi kerak.

  /// Bo'sh qoralama yaratadi va id qaytaradi.
  Future<int> createDraft({
    Map<String, dynamic>? payload,
    String? currentStep,
  }) async {
    final body = await _sendJson(
      'POST',
      _uri('/listings/drafts'),
      {'payload': payload ?? const {}, 'current_step': currentStep},
      expect: 201,
    );
    final id = body['id'];
    if (id is! int) throw BozorApiException('qoralama id kelmadi');
    return id;
  }

  /// Qoralamani yangilaydi.
  ///
  /// ⚠️ `payload` TO'LIQ ALMASHTIRILADI — qismli birlashtirish YO'Q. Shuning
  /// uchun har qadamda butun qoralama yuboriladi, aks holda oldingi
  /// qadamlarning ma'lumoti o'chib ketardi.
  Future<void> updateDraft(
    int id, {
    required Map<String, dynamic> payload,
    String? currentStep,
  }) async {
    await _sendJson(
      'PATCH',
      _uri('/listings/drafts/$id'),
      {'payload': payload, 'current_step': currentStep},
      expect: 200,
    );
  }

  /// Mening tugatilmagan qoralamalarim — oxirgi tegilgani birinchi.
  Future<List<BozorDraftSummary>> drafts() async {
    final body = await _getJson(_uri('/listings/drafts'));
    return [
      for (final e in (body['items'] as List? ?? const []))
        if (e is Map) BozorDraftSummary.fromJson(e.cast<String, dynamic>()),
    ];
  }

  Future<void> deleteDraft(int id) async {
    try {
      final res = await _client
          .delete(_uri('/listings/drafts/$id'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      // 204 — tana bo'sh. 404 ni ham muvaffaqiyat deb qaraymiz: qoralama
      // allaqachon yo'q bo'lsa foydalanuvchi uchun natija bir xil.
      if (res.statusCode != 204 && res.statusCode != 404) {
        throw BozorApiException(_errorOf(res), statusCode: res.statusCode);
      }
    } on TimeoutException {
      throw BozorApiException('server vaqtida javob bermadi');
    }
  }

  /// Qoralamani e'longa aylantiradi (`pending`).
  ///
  /// TANA YUBORILMAYDI — ma'lumot qoralamaning ichida. Javob
  /// `POST /listings/` bilan bir xil sxema. Muvaffaqiyatdan keyin qoralama
  /// serverda O'CHADI, ya'ni ro'yxatdan ham yo'qoladi.
  Future<Map<String, dynamic>> submitDraft(int id) async => _sendJson(
    'POST',
    _uri('/listings/drafts/$id/submit'),
    null,
    expect: 201,
    timeout: const Duration(seconds: 40),
  );

  // ── Ichki ─────────────────────────────────────────────────────────────────
  static const Map<String, String> _headers = {'Accept': 'application/json'};

  /// JSON tanali so'rov. `body` `null` bo'lsa tana YUBORILMAYDI —
  /// `submit` endpointi aynan shuni kutadi.
  Future<Map<String, dynamic>> _sendJson(
    String method,
    Uri uri,
    Map<String, dynamic>? body, {
    required int expect,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final req = http.Request(method, uri)
        ..headers.addAll(_headers);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final streamed = await _client.send(req).timeout(timeout);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != expect) {
        throw BozorApiException(_errorOf(res), statusCode: res.statusCode);
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw BozorApiException('javob notoʻgʻri formatda');
      }
      return decoded;
    } on TimeoutException {
      throw BozorApiException('server vaqtida javob bermadi');
    } on FormatException {
      throw BozorApiException('javob JSON emas');
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw BozorApiException(_errorOf(res), statusCode: res.statusCode);
      }
      // Baytlarni UTF-8 deb o'qiymiz: javobda charset bo'lmasa `http` paketi
      // latin1 ga tushib qoladi va kirill matn buziladi.
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw BozorApiException('javob notoʻgʻri formatda');
      }
      return decoded;
    } on TimeoutException {
      throw BozorApiException('server vaqtida javob bermadi');
    } on FormatException {
      throw BozorApiException('javob JSON emas');
    }
  }

  /// FastAPI xatosini odam o'qiydigan matnga aylantiradi.
  static String _errorOf(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final detail = body is Map ? body['detail'] : null;
      if (detail is String) return detail;
      // 422 — validatsiya: [{loc:[...], msg:"..."}]
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          final loc = (first['loc'] as List?)?.whereType<String>().toList();
          final field = (loc != null && loc.length > 1) ? '${loc.last}: ' : '';
          return '$field${first['msg']}';
        }
      }
    } catch (_) {
      // pastdagi umumiy matnga tushamiz
    }
    return 'HTTP ${res.statusCode}';
  }
}

// ── Modellar ────────────────────────────────────────────────────────────────
class ListingReference {
  const ListingReference({
    required this.dealTypes,
    required this.kinds,
    required this.types,
    required this.kindTypes,
    required this.topTierEnabled,
    required this.saleEnabled,
  });

  final List<ListingOption> dealTypes;
  final List<ListingOption> kinds;
  final List<ListingOption> types;

  /// Toifa kodi → unga tegishli tur kodlari.
  final Map<String, List<String>> kindTypes;

  /// "Top" tarifi adminkadan yoqilganmi. O'chiq bo'lsa karta ko'rsatilmaydi.
  final bool topTierEnabled;

  /// Sotuv ("Продажа") oqimi yoqilganmi. Sotuv sehrgari hali yarim — narx
  /// qadami ijara yorliqlarini ko'rsatadi va "Сделка" qadami yo'q — shu
  /// sababli bayroq o'chiq bo'lsa 1-qadamda sotuv varianti berilmaydi.
  final bool saleEnabled;

  factory ListingReference.fromJson(Map<String, dynamic> j) {
    List<ListingOption> opts(String key) => [
      for (final o in (j[key] as List? ?? const []))
        if (o is Map) ListingOption.fromJson(o.cast<String, dynamic>()),
    ];
    final kt = (j['kind_types'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ListingReference(
      dealTypes: opts('deal_types'),
      kinds: opts('kinds'),
      types: opts('types'),
      kindTypes: {
        for (final e in kt.entries)
          e.key: [for (final v in (e.value as List? ?? const [])) v.toString()],
      },
      topTierEnabled: j['top_tier_enabled'] == true,
      // `== true` ataylab: maydon yo'q bo'lsa (bayroqdan oldingi server)
      // yoki `null` kelsa `false` chiqadi — xavfsiz taraf.
      saleEnabled: j['sale_enabled'] == true,
    );
  }
}

/// Viloyat (yoki tuman) tuguni. `id` — INT: backend shunday qaytaradi.
class RegionNode {
  const RegionNode({required this.id, required this.name, this.districts = const []});

  final int id;
  final String name;
  final List<RegionNode> districts;

  factory RegionNode.fromJson(Map<String, dynamic> j) => RegionNode(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? '').toString(),
    districts: [
      for (final d in (j['districts'] as List? ?? const []))
        if (d is Map) RegionNode.fromJson(d.cast<String, dynamic>()),
    ],
  );

  @override
  bool operator ==(Object other) => other is RegionNode && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class UploadedMedia {
  const UploadedMedia({required this.key, required this.url});

  final String key;
  final String url;

  factory UploadedMedia.fromJson(Map<String, dynamic> j) => UploadedMedia(
    key: (j['key'] ?? '').toString(),
    url: (j['url'] ?? '').toString(),
  );
}
