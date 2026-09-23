/// Serverdan KELGAN e'lon — `ListingOut` javobining mobil ko'rinishi.
///
/// [BozorDraft] bilan aralashtirmaslik kerak: u YOZISH modeli (sehrgar
/// yig'adigan qoralama, `POST /listings/`), bu esa O'QISH modeli — lenta,
/// "Mening e'lonlarim" va detal ekrani AYNAN shu turni ishlatadi. Uchtasi
/// uchun bitta model, aks holda ular ajralib ketardi.
///
/// ⚠️ Backend `Decimal` maydonlarni JSON'da SATR bo'lib beradi
/// (`"price_amount": "4500000.00"`, `"area_sqm": "78.50"`), `params` ichida
/// esa oddiy son (`78.5`) — shuning uchun har bir son [_toDouble] orqali
/// o'qiladi, `as double` bilan emas.
library;

import 'package:flutter/widgets.dart';

import '../../../core/i18n/app_translations.dart';
import 'bozor_draft.dart';
import 'parcel_boundary.dart';
import 'tour_link.dart';

/// Moderatsiya holati.
///
/// [unknown] ataylab bor: server yangi holat qo'shsa (masalan `expired`)
/// telefondagi eski ilova parsingda yiqilmasligi kerak — noma'lum qiymat
/// [unknown] ga tushadi va xom kodi [BozorListing.statusCode] da qoladi.
enum ListingStatus { pending, approved, rejected, archived, unknown }

extension ListingStatusX on ListingStatus {
  static ListingStatus fromCode(String? code) => switch (code) {
    'pending' => ListingStatus.pending,
    'approved' => ListingStatus.approved,
    'rejected' => ListingStatus.rejected,
    'archived' => ListingStatus.archived,
    _ => ListingStatus.unknown,
  };

  /// Ekranda ko'rinadigan yorliq. Noma'lum holat uchun yorliq YO'Q — chaqiruvchi
  /// `null` bo'lsa badge'ni umuman chizmaydi (soxta matn ko'rsatgandan yaxshi).
  String? label(Locale l) => switch (this) {
    ListingStatus.pending => tr(l, 'listings.status.moderation'),
    ListingStatus.approved => tr(l, 'listings.status.approved'),
    ListingStatus.rejected => tr(l, 'listings.status.rejected'),
    ListingStatus.archived => tr(l, 'listings.status.archived'),
    ListingStatus.unknown => null,
  };
}

/// E'longa bog'langan fayl — foto, planirovka yoki 360°.
@immutable
class BozorListingMedia {
  const BozorListingMedia({
    required this.id,
    required this.role,
    required this.storageKey,
    required this.url,
    this.thumbUrl,
    this.title,
    this.isCover = false,
    this.sortOrder = 0,
  });

  final int id;

  /// `photo` | `plan` | `panorama` — backend `MEDIA_ROLES`.
  final String role;

  /// S3 kaliti. Tahrirlashda kerak: `PATCH` media ro'yxatini TO'LIQ
  /// almashtiradi, ya'ni SAQLANADIGAN rasmlar kalit bilan qaytariladi.
  /// Qo'shimcha oshkoralik emas — [url] ning o'zi shu kalitdan quriladi.
  final String storageKey;

  final String url;
  final String? thumbUrl;

  /// Xona nomi (360° panorama), foto/planirovkada `null`.
  final String? title;
  final bool isCover;
  final int sortOrder;

  bool get isPhoto => role == 'photo';

  /// Ro'yxatda chiziladigan havola: thumbnail bo'lsa u, aks holda asl fayl.
  /// Bo'sh satr `null` ga aylanadi — lokal muhitda S3 sozlanmagan bo'lsa
  /// backend bo'sh/nisbiy URL qaytaradi va `Image.network` bo'shda yiqiladi.
  String? get displayUrl {
    final t = thumbUrl?.trim();
    if (t != null && t.isNotEmpty) return t;
    final u = url.trim();
    return u.isEmpty ? null : u;
  }

  factory BozorListingMedia.fromJson(Map<String, dynamic> j) =>
      BozorListingMedia(
        id: _toInt(j['id']) ?? 0,
        role: (j['role'] ?? '').toString(),
        // Eski server bu maydonni qaytarmaydi — bo'sh satr bo'lib qoladi va
        // tahrirlashda o'sha rasm ro'yxatga qo'shilmaydi (yo'qolmaydi:
        // media umuman yuborilmasa server unga tegmaydi).
        storageKey: (j['storage_key'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        thumbUrl: _toStringOrNull(j['thumb_url']),
        title: _toStringOrNull(j['title']),
        isCover: j['is_cover'] == true,
        sortOrder: _toInt(j['sort_order']) ?? 0,
      );
}

@immutable
class BozorListing {
  const BozorListing({
    required this.id,
    required this.statusCode,
    required this.title,
    required this.dealType,
    required this.propertyKind,
    required this.propertyType,
    required this.address,
    required this.priceAmount,
    required this.priceCurrency,
    required this.negotiable,
    required this.contactName,
    required this.contactPhone,
    required this.createdAt,
    this.regionId,
    this.districtId,
    this.regionName,
    this.districtName,
    this.landmark,
    this.apartmentNumber,
    this.entrance,
    this.houseNumber,
    this.floor,
    this.totalFloors,
    this.latitude,
    this.longitude,
    this.cadastreNumber,
    this.boundary,
    this.rooms,
    this.areaSqm,
    this.params = const {},
    this.saleType,
    this.ownershipYears,
    this.ownersCount,
    this.registeredCount,
    this.mortgage = false,
    this.pricePeriod,
    this.priceUzs,
    this.dailyAmount,
    this.dailyCurrency,
    this.description,
    this.youtubeUrl,
    this.contactPhones = const [],
    this.contactEmail,
    this.contactPhoneVerified = false,
    this.tier = 'standard',
    this.topRank = 0,
    this.rejectionReason,
    this.moderatedAt,
    this.publishedAt,
    this.media = const [],
    this.tour = const [],
  });

  final int id;

  /// Holatning XOM kodi — [status] `unknown` bo'lganda ham nima kelganini
  /// bilish uchun saqlanadi (log, "Batafsil" ekranidagi diagnostika).
  final String statusCode;

  final String title;

  /// `rent` | `sale` — backend `DEAL_TYPES`.
  final String dealType;

  /// `residential` | `non_residential`.
  final String propertyKind;

  /// `apartment` | `house` | `land` | `commercial` | `garage` |
  /// `other_non_residential`.
  final String propertyType;

  final int? regionId;
  final int? districtId;
  final String? regionName;
  final String? districtName;
  final String address;
  final String? landmark;
  final String? apartmentNumber;
  final String? entrance;
  final String? houseNumber;
  final int? floor;
  final int? totalFloors;
  final double? latitude;
  final double? longitude;

  /// Geoportaldan tanlangan uchastkaning kadastr raqami — bo'lmasligi mumkin
  /// (manzil qo'lda belgilangan e'lonlarda `null`).
  final String? cadastreNumber;

  /// O'sha uchastkaning chegarasi — e'lon sahifasidagi xaritada chiziladi.
  final ParcelBoundary? boundary;

  /// Xonalar soni — `params.rooms_count` dan server hisoblab qo'ygan ustun.
  final int? rooms;

  /// Asosiy maydon (m²) — mulk turiga qarab `total_area`/`land_area`/… dan.
  final double? areaSqm;

  /// Qolgan ~50 parametr. Kalitlari `param_schema.dart` bilan bir xil,
  /// qiymatlari KOD (`renovation: "euro"`), yorlig'i `/listings/options` dan.
  final Map<String, dynamic> params;

  // ── «Сделка» — ijara e'lonlarida to'rttasi ham `null` ───────────────────
  // Qiymatlar KOD (`free_sale`, `under_3`, `6_plus`); yorliqlari
  // `/listings/options` dan, `params` bilan bir xil qoida.
  final String? saleType;
  final String? ownershipYears;
  final String? ownersCount;

  /// «Прописано» — faqat kvartira turlarida so'raladi.
  final String? registeredCount;

  final double priceAmount;
  final String priceCurrency;

  /// `month` | `day` — sotuvda `null`.
  final String? pricePeriod;

  /// So'mga normallashtirilgan narx — lenta filtri va saralashi shu bo'yicha.
  final double? priceUzs;

  final bool negotiable;
  final double? dailyAmount;
  final String? dailyCurrency;

  /// «Ипотека» — faqat sotuvda ma'noli, ijarada har doim `false`.
  final bool mortgage;

  final String? description;
  final String? youtubeUrl;

  final String contactName;
  final String contactPhone;
  final List<String> contactPhones;
  final String? contactEmail;
  final bool contactPhoneVerified;

  /// `standard` | `top` — "Top" tarifi hali pulli emas (adminka qo'yadi).
  final String tier;
  final int topRank;

  /// Faqat EGASIGA keladi: ommaviy lentada backend uni `null` qilib tashlaydi.
  final String? rejectionReason;

  final DateTime? moderatedAt;
  final DateTime? publishedAt;
  final List<BozorListingMedia> media;

  /// 360° tur havolalari — uchlari `media` dagi `panorama` rolli
  /// fayllarning `storage_key` lari.
  final List<TourLink> tour;
  final DateTime createdAt;

  // ── Hosila qiymatlar ──────────────────────────────────────────────────────
  ListingStatus get status => ListingStatusX.fromCode(statusCode);

  bool get isTop => tier == 'top';

  List<BozorListingMedia> get photos => [
    for (final m in media)
      if (m.isPhoto) m,
  ];

  /// Kartaning muqova rasmi. Tartib: `is_cover` belgilangan foto → birinchi
  /// foto → boshqa har qanday fayl (planirovka ham rasm bo'lishi mumkin).
  /// Rasm umuman bo'lmasa `null` — chaqiruvchi placeholder chizadi.
  String? get coverImageUrl {
    for (final m in photos) {
      if (m.isCover && m.displayUrl != null) return m.displayUrl;
    }
    for (final m in photos) {
      if (m.displayUrl != null) return m.displayUrl;
    }
    for (final m in media) {
      if (m.displayUrl != null) return m.displayUrl;
    }
    return null;
  }

  /// Detal galereyasi — muqova birinchi bo'lib, faqat fotolar.
  List<String> get galleryUrls {
    final list = [...photos]
      ..sort((a, b) {
        if (a.isCover != b.isCover) return a.isCover ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    return [
      for (final m in list) ?m.displayUrl,
    ];
  }

  /// "Toshkent sh., Chilonzor tumani" — viloyat/tuman nomlari bo'lmasa
  /// (`region_id` yuborilmagan e'lonlarda ular `null`) bo'sh satr.
  String get regionLine =>
      [regionName, districtName].whereType<String>().join(', ');

  /// "4 500 000 so'm/oy" — kartadagi va detaldagi asosiy narx qatori.
  String formattedPrice(Locale l) =>
      '${formatBozorAmount(priceAmount)} ${_currencyLabel(l, priceCurrency)}'
      '${_periodSuffix(l, pricePeriod)}';

  /// Sutkalik narx — faqat ijarada va faqat kiritilgan bo'lsa.
  String? formattedDailyPrice(Locale l) {
    final amount = dailyAmount;
    if (amount == null) return null;
    return '${formatBozorAmount(amount)} '
        '${_currencyLabel(l, dailyCurrency ?? priceCurrency)}'
        '${_periodSuffix(l, 'day')}';
  }

  /// "3 xona · 78,5 m²". Ikkisi ham yo'q bo'lsa (yer uchastkasida xona
  /// bo'lmasligi mumkin) `null` — qator umuman chizilmaydi.
  String? roomsAreaLine(Locale l) {
    final parts = <String>[
      if (rooms != null && rooms! > 0) '$rooms ${tr(l, 'bozor.listing.rooms_short')}',
      if (areaSqm != null) '${formatBozorAmount(areaSqm!)} ${tr(l, 'bozor.unit.m²')}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Mulk turining shu tildagi nomi. Kodlar sehrgardagi [PropertyType] bilan
  /// bir xil, shuning uchun yorliq kalitlari QAYTA yozilmaydi.
  String propertyTypeLabel(Locale l) => switch (propertyType) {
    'apartment' => PropertyType.apartment.label(l),
    'house' => PropertyType.house.label(l),
    'land' => PropertyType.land.label(l),
    'commercial' => PropertyType.commercial.label(l),
    'garage' => PropertyType.garage.label(l),
    'basement' => PropertyType.basement.label(l),
    'other_non_residential' => PropertyType.otherNonResidential.label(l),
    // Server yangi tur qo'shsa xom kod ko'rinadi — greplanadi, ilova tirik.
    _ => propertyType,
  };

  String dealTypeLabel(Locale l) => switch (dealType) {
    'rent' => DealType.rent.label(l),
    'sale' => DealType.sale.label(l),
    _ => dealType,
  };

  factory BozorListing.fromJson(Map<String, dynamic> j) => BozorListing(
    id: _toInt(j['id']) ?? 0,
    statusCode: (j['status'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    dealType: (j['deal_type'] ?? '').toString(),
    propertyKind: (j['property_kind'] ?? '').toString(),
    propertyType: (j['property_type'] ?? '').toString(),
    regionId: _toInt(j['region_id']),
    districtId: _toInt(j['district_id']),
    regionName: _toStringOrNull(j['region_name']),
    districtName: _toStringOrNull(j['district_name']),
    address: (j['address'] ?? '').toString(),
    landmark: _toStringOrNull(j['landmark']),
    apartmentNumber: _toStringOrNull(j['apartment_number']),
    entrance: _toStringOrNull(j['entrance']),
    houseNumber: _toStringOrNull(j['house_number']),
    floor: _toInt(j['floor']),
    totalFloors: _toInt(j['total_floors']),
    latitude: _toDouble(j['latitude']),
    longitude: _toDouble(j['longitude']),
    cadastreNumber: _nonEmpty(j['cadastre_number']),
    boundary: ParcelBoundary.fromGeoJson(j['boundary']),
    rooms: _toInt(j['rooms']),
    areaSqm: _toDouble(j['area_sqm']),
    params: (j['params'] as Map?)?.cast<String, dynamic>() ?? const {},
    saleType: _toStringOrNull(j['sale_type']),
    ownershipYears: _toStringOrNull(j['ownership_years']),
    ownersCount: _toStringOrNull(j['owners_count']),
    registeredCount: _toStringOrNull(j['registered_count']),
    priceAmount: _toDouble(j['price_amount']) ?? 0,
    priceCurrency: (j['price_currency'] ?? 'UZS').toString(),
    pricePeriod: _toStringOrNull(j['price_period']),
    priceUzs: _toDouble(j['price_uzs']),
    negotiable: j['negotiable'] == true,
    dailyAmount: _toDouble(j['daily_amount']),
    dailyCurrency: _toStringOrNull(j['daily_currency']),
    // Bayroqdan oldingi server bu maydonni yubormaydi — `false` qoladi.
    mortgage: j['mortgage'] == true,
    description: _toStringOrNull(j['description']),
    youtubeUrl: _toStringOrNull(j['youtube_url']),
    contactName: (j['contact_name'] ?? '').toString(),
    contactPhone: (j['contact_phone'] ?? '').toString(),
    contactPhones: [
      for (final p in (j['contact_phones'] as List? ?? const [])) p.toString(),
    ],
    contactEmail: _toStringOrNull(j['contact_email']),
    contactPhoneVerified: j['contact_phone_verified'] == true,
    tier: (j['tier'] ?? 'standard').toString(),
    topRank: _toInt(j['top_rank']) ?? 0,
    rejectionReason: _toStringOrNull(j['rejection_reason']),
    moderatedAt: _toDate(j['moderated_at']),
    publishedAt: _toDate(j['published_at']),
    tour: [
      for (final t in (j['tour'] as List? ?? const []))
        if (t is Map) TourLink.fromJson(Map<String, Object?>.from(t)),
    ],
    media: [
      for (final m in (j['media'] as List? ?? const []))
        if (m is Map) BozorListingMedia.fromJson(m.cast<String, dynamic>()),
    ],
    // `created_at` NOT NULL, lekin parsing hech qachon yiqilmasligi kerak:
    // buzuq sanada e'lon ro'yxatdan tushib qolgandan ko'ra "hozir" yaxshi.
    createdAt: _toDate(j['created_at']) ?? DateTime.now(),
  );
}

/// Tugatilmagan qoralama — `DraftOut` javobining mobil ko'rinishi.
///
/// "Mening e'lonlarim" ro'yxati uchun yetarli maydonlar. Karta chizish uchun
/// kerakli to'rtta maydon ([title], [dealType], [propertyType], [address])
/// serverda payload'dan XAVFSIZ olinadi va shakli boshqacha bo'lsa `null`
/// bo'lib keladi — shu sababli bu yerda ham hammasi nullable.
///
/// [payload] — to'liq qoralama. Foydalanuvchi kartani bosganda
/// `draftFromPayload` shu maydondan sehrgarni tiklaydi, ya'ni ro'yxat uchun
/// alohida so'rov kerak emas.
@immutable
class BozorDraftSummary {
  const BozorDraftSummary({
    required this.id,
    required this.payload,
    this.currentStep,
    this.title,
    this.dealType,
    this.propertyType,
    this.address,
    this.updatedAt,
  });

  final int id;
  final Map<String, dynamic> payload;

  /// Foydalanuvchi qaysi qadamda qolgan (`type`, `address`, …). `null` —
  /// noma'lum, resume 1-qadamdan boshlanadi.
  final String? currentStep;

  final String? title;
  final String? dealType;
  final String? propertyType;
  final String? address;
  final DateTime? updatedAt;

  factory BozorDraftSummary.fromJson(Map<String, dynamic> j) {
    final raw = j['payload'];
    return BozorDraftSummary(
      id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      payload: raw is Map
          ? raw.map((k, v) => MapEntry(k.toString(), v))
          : const {},
      currentStep: j['current_step']?.toString(),
      title: _nonEmpty(j['title']),
      dealType: _nonEmpty(j['deal_type']),
      propertyType: _nonEmpty(j['property_type']),
      address: _nonEmpty(j['address']),
      updatedAt: DateTime.tryParse('${j['updated_at']}'),
    );
  }
}

/// Bo'sh satr ham `null` bilan bir xil — karta bo'sh qatorni chizmasin.
String? _nonEmpty(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Sahifalangan javob — `ListingListResponse` (`items` + `total` + `page` +
/// `size`). Backend cursor ISHLATMAYDI, `page`/`size` bilan sahifalaydi.
@immutable
class BozorListingPage {
  const BozorListingPage({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  static const BozorListingPage empty = BozorListingPage(
    items: [],
    total: 0,
    page: 1,
    size: 0,
  );

  final List<BozorListing> items;
  final int total;
  final int page;
  final int size;

  /// Yana sahifa bormi. `size` ni emas, KELGAN qatorlar sonini ham hisobga
  /// olamiz: oxirgi sahifa to'liq bo'lmasa keyingisi ham bo'lmaydi.
  bool get hasMore => (page - 1) * size + items.length < total;

  int get nextPage => page + 1;

  factory BozorListingPage.fromJson(Map<String, dynamic> j) => BozorListingPage(
    items: [
      for (final i in (j['items'] as List? ?? const []))
        if (i is Map) BozorListing.fromJson(i.cast<String, dynamic>()),
    ],
    total: _toInt(j['total']) ?? 0,
    page: _toInt(j['page']) ?? 1,
    size: _toInt(j['size']) ?? 0,
  );
}

// ── Parsing yordamchilari ───────────────────────────────────────────────────
// Backend `Decimal` ni satr, `int` ni son qilib beradi; `params` ichida esa
// bir xil maydon ikki xil turda kelishi mumkin. Shu sababli har biri
// `toString()` orqali o'tadi.
int? _toInt(Object? v) => switch (v) {
  null => null,
  final int i => i,
  final num n => n.toInt(),
  _ => int.tryParse(v.toString()) ?? double.tryParse(v.toString())?.toInt(),
};

double? _toDouble(Object? v) => switch (v) {
  null => null,
  final num n => n.toDouble(),
  _ => double.tryParse(v.toString()),
};

/// Bo'sh satrni ham `null` deb qaraydi — UI'da bo'sh qator chizilmasin.
String? _toStringOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _toDate(Object? v) {
  if (v == null) return null;
  // Backend UTC beradi (`...Z`), lokal vaqtga o'giramiz — ekranlarda sana
  // foydalanuvchi mintaqasida ko'rinishi kerak.
  return DateTime.tryParse(v.toString())?.toLocal();
}

/// "4 500 000" / "78,5" — mingliklar ajratilgan, keraksiz nollar olib
/// tashlangan.
///
/// OMMAVIY: detal ekrani ham (maydon nishoni, sonli parametrlar) SHU
/// funksiyani ishlatadi. Ilgari u yerda aynan nusxasi turardi — ikkita
/// mustaqil formatlovchi vaqt o'tib ajralib ketadi.
String formatBozorAmount(num value) {
  final negative = value < 0;
  final abs = value.abs();
  final whole = abs.truncate();
  // Kasr qismi faqat maydonda ma'noli (78,5 m²); narxda `.00` bo'lib keladi.
  final fraction = abs - whole;
  final buf = StringBuffer();
  final digits = whole.toString();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  if (fraction > 0) {
    final f = fraction.toStringAsFixed(2).substring(2).replaceAll(RegExp(r'0+$'), '');
    if (f.isNotEmpty) buf.write(',$f');
  }
  return '${negative ? '-' : ''}$buf';
}

String _currencyLabel(Locale l, String code) => switch (code.toUpperCase()) {
  'UZS' => tr(l, 'bozor.listing.currency.uzs'),
  'USD' => r'$',
  // Notanish valyuta kodi o'zi ko'rinadi — tarjimasi yo'qligi ko'zga tashlanadi.
  _ => code,
};

String _periodSuffix(Locale l, String? period) => switch (period) {
  'month' => tr(l, 'bozor.listing.period.month'),
  'day' => tr(l, 'bozor.listing.period.day'),
  _ => '',
};
