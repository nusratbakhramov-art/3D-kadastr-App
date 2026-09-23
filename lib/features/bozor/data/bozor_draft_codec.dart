/// `BozorDraft` ↔ backend payload o'girmasi.
///
/// Ikki yo'nalish BITTA faylda turadi va bir xil kalitlarni ishlatadi —
/// aks holda yozish (`submit`) va o'qish (`resume`) vaqt o'tib bir-biridan
/// ajralib ketardi va foydalanuvchi qoralamaga qaytganda maydonlarning
/// yarmi bo'sh chiqardi.
///
/// Payload shakli AYNAN backend `ListingCreateRequest` (`app/schemas/
/// bozor_listing.py`): shu sabab `POST /listings/drafts/{id}/submit` qo'shimcha
/// o'girish talab qilmaydi — server qoralamaning payload'ini to'g'ridan-to'g'ri
/// validatsiya qiladi.
///
/// TO'LIQ BO'LMAGAN qoralamaga RUXSAT: [draftToPayload] `null` qiymatlarni
/// ham yozadi (foydalanuvchi 2-qadamda chiqib ketgan bo'lishi mumkin).
/// Serverda `POST /drafts` validatsiya QILMAYDI, `submit` esa qiladi — ya'ni
/// yarim qoralama saqlanadi, lekin e'lon bo'lib chiqmaydi.
library;

import '../models/bozor_draft.dart';
import '../models/parcel_boundary.dart';
import '../models/tour_link.dart';
import '../models/bozor_listing.dart';

// ── Enum ↔ kod ──────────────────────────────────────────────────────────────
// Nomlar `app/schemas/listing_options.py` bilan AYNAN bir xil. Ikki yo'nalish
// yonma-yon turadi: bittasi o'zgarsa ikkinchisi ham ko'zga tashlanadi.

extension DealTypeCode on DealType {
  String get code => switch (this) {
    DealType.rent => 'rent',
    DealType.sale => 'sale',
  };
}

extension PropertyKindCode on PropertyKind {
  String get code => switch (this) {
    PropertyKind.residential => 'residential',
    PropertyKind.nonResidential => 'non_residential',
  };
}

// `PropertyType.code` — endi `bozor_draft.dart` da (sxema yuklovchisi ham
// o'sha kodni ishlatadi, kodek esa uni import qila olmaydi).

extension PlacementTierCode on PlacementTier {
  String get code => switch (this) {
    PlacementTier.standard => 'standard',
    PlacementTier.top => 'top',
  };
}

/// Noma'lum kod `null` beradi — server yangi qiymat qo'shsa eski ilova
/// yiqilmaydi, shunchaki o'sha maydonni bo'sh ko'rsatadi.
DealType? dealTypeFromCode(Object? code) => switch (code) {
  'rent' => DealType.rent,
  'sale' => DealType.sale,
  _ => null,
};

PropertyKind? propertyKindFromCode(Object? code) => switch (code) {
  'residential' => PropertyKind.residential,
  'non_residential' => PropertyKind.nonResidential,
  _ => null,
};

PropertyType? propertyTypeFromCode(Object? code) => switch (code) {
  'apartment' => PropertyType.apartment,
  'new_building_apartment' => PropertyType.newBuildingApartment,
  'house' => PropertyType.house,
  'land' => PropertyType.land,
  'commercial' => PropertyType.commercial,
  'garage' => PropertyType.garage,
  'basement' => PropertyType.basement,
  'other_non_residential' => PropertyType.otherNonResidential,
  _ => null,
};

PlacementTier placementTierFromCode(Object? code) =>
    code == 'top' ? PlacementTier.top : PlacementTier.standard;

// ── Narx birligi ────────────────────────────────────────────────────────────
// `PriceDraft.unit` — `bozor_price_step_screen.dart` dagi QAT'IY tokenlar
// (`UZS/oy`, `USD/oy`, `UZS`, `USD`), tarjima qilinmaydi. Shu sababli
// valyuta + davr → token o'girmasi bir qiymatli.

/// `UZS/oy` → `UZS`.
String currencyOfUnit(String unit) => unit.split('/').first.trim();

/// `UZS/oy` → `month`; davrsiz token → `null`.
String? periodOfUnit(String unit) {
  if (!unit.contains('/')) return null;
  final suffix = unit.split('/').last.trim().toLowerCase();
  return switch (suffix) {
    'oy' || 'мес' || 'mo' => 'month',
    'kun' || 'сут' || 'day' => 'day',
    _ => null,
  };
}

/// Teskarisi: `UZS` + `month` → `UZS/oy`.
String unitFromCurrency(Object? currency, Object? period) {
  final c = (currency ?? 'UZS').toString();
  return switch (period) {
    'month' => '$c/oy',
    'day' => '$c/kun',
    _ => c,
  };
}

// ── Yozish ──────────────────────────────────────────────────────────────────

/// Qoralamaning MAHALLIY fayl yo'llari uchun kalit.
///
/// Rasmlar e'lon yuborilgunicha yuklanmaydi, ya'ni qoralamada faqat qurilma
/// yo'llari bor. Backend `ListingCreateRequest` da `extra="forbid"` YO'Q
/// (pydantic sukut bo'yicha notanish kalitni jimgina tashlaydi), shuning
/// uchun bu kalit `submit` ni buzmaydi — tekshirilgan.
const String kLocalMediaKey = '_local_media';

/// Qoralama MAVJUD e'londan ochilganini bildiruvchi kalit.
///
/// ⚠️ BUSIZ TAHRIRLASH JIMGINA YANGI E'LON YASARDI. Sehrgar har qadamda
/// qoralamani saqlaydi — tahrirlashda ham. Foydalanuvchi sehrgardan
/// chiqib, keyin «Mening e'lonlarim» dagi qoralamadan davom ettirsa,
/// `draftFromPayload` faqat `draftId` ni tiklardi va `editingListingId`
/// NULL bo'lib qolardi. Yuborishda esa shu maydon `PATCH /listings/{id}`
/// bilan `POST /drafts/{id}/submit` orasidagi yagona ayirg'ich — ya'ni
/// tahrir NUSXA bo'lib ketardi, asl e'lon esa o'zgarmasdan qolardi.
const String kEditingListingKey = '_editing_listing_id';

/// Ro'yxatdagi qoralama MAVJUD e'lonning tahriri bo'lsa — o'sha e'lon id'si.
///
/// Qoralamani to'liq tiklamasdan (`draftFromPayload`) javob beradi: chaqiruvi
/// ikkita — saqlashda TAKRORNI oldini olish va kartada «Tahrirlanmoqda»
/// nishonini ko'rsatish. Ikkalasiga ham faqat shu bitta son kerak.
int? editingListingIdOf(BozorDraftSummary draft) =>
    _int(draft.payload[kEditingListingKey]);

/// Serverda ALLAQACHON turgan fayllar (tahrirlash uchun).
///
/// ⚠️ BUSIZ TAHRIRLASHNI DAVOM ETTIRISH RASMLARNI O'CHIRARDI. `PATCH`
/// media ro'yxatini TO'LIQ almashtiradi, ya'ni yuborishda eski fayllar
/// kalitlari bilan QAYTA yuborilishi shart. Qoralamadan tiklanganda bu
/// ro'yxat bo'sh bo'lsa, e'lonning bor rasmlari o'rniga faqat shu
/// sessiyada qo'shilganlari qolardi.
const String kExistingMediaKey = '_existing_media';

/// Qoralama uchun payload: [draftToPayload] ning media'siz varianti +
/// mahalliy fayl yo'llari.
Map<String, dynamic> draftToDraftPayload(BozorDraft draft) {
  final d = draft.description;
  return {
    ...draftToPayload(draft, const []),
    // Rasmlar hali S3 da yo'q — qurilma yo'llarini saqlaymiz, aks holda
    // qoralamaga qaytgan foydalanuvchi tanlagan rasmlarini yo'qotardi.
    kLocalMediaKey: {
      'photos': List<String>.from(d.photos),
      // Tanlangan muqova — HAVOLA bo'yicha, indeks bo'yicha emas.
      'cover_photo': ?d.coverPhoto,
      'plan': List<String>.from(d.planFiles),
      'panorama': List<String>.from(d.panoramas),
      // Panorama kalitlarining ko'rsatish URL'lari — viewer/tur uchun.
      'panorama_urls': Map<String, String>.from(d.panoramaUrls),
      // HALI TIKILAYOTGANLAR. Busiz ilova yopilib ochilganda kuzatuv
      // uzilardi: `panoramas` da `job:<id>` havolasi qolib, uni hech kim
      // haqiqiy kalitga almashtirmasdi va e'lon abadiy yuborilmas bo'lardi.
      'pending_panorama': {
        for (final e in d.pendingPanoramas.entries) e.key: e.value.toJson(),
      },
      // TELEFONDA saqlangan tushirishlar (kadrlar diskda, yuklanmagan).
      // Busiz ilova yopilib ochilganda `local:` havola egasiz qolardi.
      'local_panorama': {
        for (final e in d.localPanoramas.entries) e.key: e.value.toJson(),
      },
      // Xona nomlari (havola → nom).
      'panorama_names': Map<String, String>.from(d.panoramaNames),
      // Allaqachon yuklangan fayllar — qayta urinish ularni takrorlamasin.
      'uploaded': Map<String, String>.from(d.uploadedMedia),
      // 360° tur havolalari. Qoralamada LOKAL YO'L bilan yotadi, ya'ni
      // `description.tour` ga (u kalit kutadi) yozib bo'lmaydi.
      'tour': [for (final l in d.tourLinks) l.toJson()],
    },
    // Tahrirlash rejimi qoralamada SAQLANADI — sababi kalit izohida.
    if (draft.editingListingId != null)
      kEditingListingKey: draft.editingListingId,
    if (d.existingMedia.isNotEmpty)
      kExistingMediaKey: [
        for (final m in d.existingMedia)
          {
            'key': m.key,
            'role': m.role,
            'sort_order': m.sortOrder,
            'is_cover': m.isCover,
            'title': ?m.title,
          },
      ],
  };
}

/// `ListingCreateRequest` shakli.
///
/// `deal`/`kind`/`type` `null` bo'lsa `null` yoziladi (qoralama to'liq
/// bo'lmasligi mumkin). `submit` da server bunga 400 beradi — bu KUTILGAN.
Map<String, dynamic> draftToPayload(
  BozorDraft draft,
  List<Map<String, Object?>> media,
) {
  final a = draft.address;
  final p = draft.price;
  final d = draft.description;
  final c = draft.contacts;

  return {
    'deal_type': draft.deal?.code,
    'property_kind': draft.kind?.code,
    'property_type': draft.type?.code,
    'title': draft.title,
    'address': {
      'region_id': a.regionId,
      'district_id': a.districtId,
      'address': a.address,
      if (a.landmark.isNotEmpty) 'landmark': a.landmark,
      if (a.apartmentNumber.isNotEmpty) 'apartment_number': a.apartmentNumber,
      if (a.entrance.isNotEmpty) 'entrance': a.entrance,
      if (a.houseNumber.isNotEmpty) 'house_number': a.houseNumber,
      if (a.floor.isNotEmpty) 'floor': int.tryParse(a.floor),
      if (a.totalFloors.isNotEmpty) 'total_floors': int.tryParse(a.totalFloors),
      if (a.lat != null) 'lat': a.lat,
      if (a.lng != null) 'lng': a.lng,
      if (a.cadastreNumber.isNotEmpty) 'cadastre_number': a.cadastreNumber,
      if (a.boundary != null) 'boundary': a.boundary!.toGeoJson(),
    },
    'params': Map<String, Object?>.from(draft.params),
    // «Сделка» — FAQAT sotuvda. Ijarada bo'lim umuman YUBORILMAYDI: backend
    // uni ijara e'lonida 400 bilan rad etadi
    // (`ListingCreateRequest.check_deal()`).
    if (draft.deal == DealType.sale)
      'deal': {
        'sale_type': draft.transaction.saleType,
        'ownership_years': draft.transaction.ownershipYears,
        'owners_count': draft.transaction.ownersCount,
        // «Прописано» so'ralmaydigan turda `null` — backend notanish turda
        // qiymat kelsa 400 beradi.
        'registered_count': (draft.type?.asksRegisteredCount ?? false)
            ? draft.transaction.registeredCount
            : null,
      },
    'price': {
      'amount': num.tryParse(p.amount) ?? 0,
      'currency': currencyOfUnit(p.unit),
      'period': periodOfUnit(p.unit),
      'negotiable': p.negotiable,
      // «Ипотека» ham faqat sotuvda — ijarada `true` yuborilsa 400.
      'mortgage': draft.deal == DealType.sale && p.mortgage,
      if (p.dailyAmount.isNotEmpty) ...{
        'daily_amount': num.tryParse(p.dailyAmount),
        'daily_currency': currencyOfUnit(p.dailyUnit),
      },
    },
    'description': {
      if (d.text.trim().isNotEmpty) 'text': d.text.trim(),
      if (d.youtubeUrl.isNotEmpty) 'youtube_url': d.youtubeUrl,
      'media': media,
      // ⚠️ Havolalar AYNI SHU `media` ro'yxatidan hisoblanadi. Server
      // ularni o'sha ro'yxat bilan solishtiradi, ya'ni ro'yxatga
      // tushmagan panoramaga ishora qilgan havola butun e'lonni 400 ga
      // olib borardi.
      'tour': resolveTourLinks(
        d.tourLinks,
        uploaded: d.uploadedMedia,
        allowedKeys: {
          for (final m in media)
            if (m['role'] == 'panorama' && m['key'] is String)
              m['key']! as String,
        },
      ),
    },
    'contacts': {
      'name': c.name,
      'phones': c.phones.where((s) => s.isNotEmpty).toList(),
      if (c.email.isNotEmpty) 'email': c.email,
    },
    'terms': {
      'tier': draft.terms.tier.code,
      'accepted': draft.terms.accepted,
      'terms_version': ?draft.terms.acceptedVersion,
    },
  };
}

// ── O'qish ──────────────────────────────────────────────────────────────────

/// Payload'dan qoralamani tiklaydi.
///
/// HAR BIR maydon xavfsiz o'qiladi: payload serverda validatsiyasiz
/// saqlanadi, ya'ni shakli boshqacha bo'lishi mumkin (eski ilova versiyasi
/// yozgan bo'lishi ham mumkin). Tushunarsiz maydon shunchaki bo'sh qoladi —
/// hech qanday holatda istisno tashlanmaydi.
BozorDraft draftFromPayload(Map<String, dynamic> json, {int? draftId}) {
  final draft = BozorDraft(
    deal: dealTypeFromCode(json['deal_type']),
    kind: propertyKindFromCode(json['property_kind']),
    type: propertyTypeFromCode(json['property_type']),
  )..draftId = draftId;

  // Tahrirlash rejimi — `draftToDraftPayload` yozib qo'ygan bo'lsa.
  draft.editingListingId = _int(json[kEditingListingKey]);
  for (final e in (json[kExistingMediaKey] as List? ?? const [])) {
    if (e is! Map) continue;
    final key = (e['key'] ?? '').toString();
    if (key.isEmpty) continue;
    draft.description.existingMedia.add(
      ExistingMedia(
        key: key,
        role: (e['role'] ?? 'photo').toString(),
        sortOrder: _int(e['sort_order']) ?? 0,
        isCover: e['is_cover'] == true,
        title: e['title']?.toString(),
      ),
    );
  }

  draft.title = _str(json['title']);

  final a = _map(json['address']);
  draft.address
    ..regionId = _int(a['region_id'])
    ..districtId = _int(a['district_id'])
    ..address = _str(a['address'])
    ..landmark = _str(a['landmark'])
    ..apartmentNumber = _str(a['apartment_number'])
    ..entrance = _str(a['entrance'])
    ..houseNumber = _str(a['house_number'])
    ..floor = _numStr(a['floor'])
    ..totalFloors = _numStr(a['total_floors'])
    ..lat = _double(a['lat'])
    ..lng = _double(a['lng'])
    ..cadastreNumber = _str(a['cadastre_number'])
    ..boundary = ParcelBoundary.fromGeoJson(a['boundary']);

  // `setType` params'ni tozalaydi, shuning uchun params'ni turdan KEYIN
  // to'ldiramiz — aks holda 3-qadam qiymatlari yo'qolardi.
  final params = _map(json['params']);
  draft.params
    ..clear()
    ..addAll(params);

  final deal = _map(json['deal']);
  draft.transaction
    ..saleType = _strOrNull(deal['sale_type'])
    ..ownershipYears = _strOrNull(deal['ownership_years'])
    ..ownersCount = _strOrNull(deal['owners_count'])
    ..registeredCount = _strOrNull(deal['registered_count']);

  final p = _map(json['price']);
  draft.price
    ..mortgage = p['mortgage'] == true
    ..amount = _numStr(p['amount'])
    ..unit = unitFromCurrency(p['currency'], p['period'])
    ..negotiable = p['negotiable'] != false
    ..dailyAmount = _numStr(p['daily_amount'])
    ..dailyUnit = _str(p['daily_currency']).isEmpty
        ? 'UZS'
        : _str(p['daily_currency']);

  final d = _map(json['description']);
  draft.description
    ..text = _str(d['text'])
    ..youtubeUrl = _str(d['youtube_url']);
  // Mahalliy yo'llar — [kLocalMediaKey] ga qarang.
  final local = _map(json[kLocalMediaKey]);
  draft.description.photos
    ..clear()
    ..addAll(_strList(local['photos']));
  // Ro'yxatda qolmagan havola tiklanmaydi — `coverPhotoIndex` baribir
  // birinchisiga tushardi, lekin qoralamada o'lik qiymat saqlanmasin.
  final cover = local['cover_photo'];
  draft.description.coverPhoto =
      (cover is String && draft.description.photos.contains(cover))
      ? cover
      : null;
  draft.description.planFiles
    ..clear()
    ..addAll(_strList(local['plan']));
  draft.description.panoramas
    ..clear()
    ..addAll(_strList(local['panorama']));
  draft.description.panoramaUrls
    ..clear()
    ..addAll({
      for (final e in _map(local['panorama_urls']).entries)
        if (e.value != null) e.key: e.value.toString(),
    });
  draft.description.pendingPanoramas
    ..clear()
    ..addAll({
      for (final e in _map(local['pending_panorama']).entries)
        if (e.value is Map)
          e.key: PendingPano.fromJson(
            (e.value as Map).cast<String, Object?>(),
          ),
    });
  draft.description.localPanoramas
    ..clear()
    ..addAll({
      for (final e in _map(local['local_panorama']).entries)
        if (e.value is Map)
          e.key: LocalPano.fromJson((e.value as Map).cast<String, Object?>()),
    });
  draft.description.panoramaNames
    ..clear()
    ..addAll({
      for (final e in _map(local['panorama_names']).entries)
        if (e.value != null && e.value.toString().trim().isNotEmpty)
          e.key: e.value.toString(),
    });
  draft.description.uploadedMedia
    ..clear()
    ..addAll({
      for (final e in _map(local['uploaded']).entries)
        if (e.value != null) e.key: e.value.toString(),
    });
  draft.description.tourLinks
    ..clear()
    ..addAll([
      for (final t in (local['tour'] as List? ?? const []))
        if (t is Map) TourLink.fromJson(Map<String, Object?>.from(t)),
    ]);

  final c = _map(json['contacts']);
  final phones = _strList(c['phones']);
  draft.contacts
    ..name = _str(c['name'])
    ..email = _str(c['email']);
  draft.contacts.phones
    ..clear()
    // Forma kamida bitta qatorni kutadi (`ContactsDraft.phones = ['']`).
    ..addAll(phones.isEmpty ? [''] : phones);

  final t = _map(json['terms']);
  draft.terms
    ..tier = placementTierFromCode(t['tier'])
    // Rozilik ATAYLAB tiklanmaydi: u har yuborishda ongli tasdiqlanishi
    // kerak (huquqiy sabab, reja Z5).
    ..accepted = false;

  return draft;
}

/// Saqlangan `current_step` dan qadam. Noma'lum qiymat 1-qadamga tushadi —
/// bo'sh ekran ko'rsatgandan yaxshi.
WizardStep wizardStepFromName(Object? name) {
  for (final s in WizardStep.values) {
    if (s.name == name) {
      return s;
    }
  }
  return WizardStep.type;
}

// ── Xavfsiz o'qish yordamchilari ────────────────────────────────────────────

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.map((k, value) => MapEntry(k.toString(), value)) : const {};

String _str(Object? v) => v == null ? '' : v.toString();

/// Bo'sh satr ham `null` — «Сделка» maydonlari tanlanmagan holatni `null`
/// bilan ifodalaydi, bo'sh satr bilan emas.
String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Son maydonlari formada MATN sifatida turadi (`floor`, `amount`).
/// `null` → bo'sh satr, `72.5` → `72.5`, `3` → `3` (`3.0` EMAS).
String _numStr(Object? v) {
  if (v == null) return '';
  if (v is int) return v.toString();
  if (v is num) {
    // Butun son matn maydonida `3` bo'lib ko'rinishi kerak, `3.0` emas.
    final whole = v == v.roundToDouble() && v.abs() < 1e15;
    return whole ? v.toInt().toString() : v.toString();
  }
  return v.toString();
}

int? _int(Object? v) => v is int ? v : int.tryParse(_str(v));

double? _double(Object? v) => v is num ? v.toDouble() : double.tryParse(_str(v));

List<String> _strList(Object? v) =>
    v is List ? [for (final e in v) e.toString()] : const [];

// ── Tahrirlash: e'lon → qoralama ────────────────────────────────────────────

/// Mavjud e'londan tahrirlash uchun qoralama quradi.
///
/// [draftFromPayload] dan farqi: manba serverdagi TO'LIQ e'lon
/// (`ListingOut`), ya'ni maydonlar tipli va ishonchli. Natijada
/// `editingListingId` to'ladi va yuborish `PATCH /listings/{id}` ga ketadi —
/// yangi e'lon YARATILMAYDI.
///
/// ⚠️ HAR BIR yangi bo'lim shu funksiyaga ham qo'shilishi SHART — aks holda
/// e'lon tahrirlanganda o'sha bo'lim qoralamaga tiklanmaydi va `PATCH` uni
/// NULL ga tushiradi (jimgina ma'lumot yo'qolishi). «Сделка» va «Ипотека»
/// qo'shilgan; keyingisi — maydon birligi (reja M4-26).
BozorDraft draftFromListing(BozorListing l) {
  final draft = BozorDraft(
    deal: dealTypeFromCode(l.dealType),
    kind: propertyKindFromCode(l.propertyKind),
    type: propertyTypeFromCode(l.propertyType),
  )..editingListingId = l.id;

  draft.title = l.title;

  draft.address
    ..regionId = l.regionId
    ..regionName = l.regionName
    ..districtId = l.districtId
    ..districtName = l.districtName
    ..address = l.address
    ..landmark = l.landmark ?? ''
    ..apartmentNumber = l.apartmentNumber ?? ''
    ..entrance = l.entrance ?? ''
    ..houseNumber = l.houseNumber ?? ''
    ..floor = l.floor?.toString() ?? ''
    ..totalFloors = l.totalFloors?.toString() ?? ''
    ..lat = l.latitude
    ..lng = l.longitude
    ..cadastreNumber = l.cadastreNumber ?? ''
    ..boundary = l.boundary;

  // Tur `BozorDraft` konstruktorida berilgani uchun `setType` chaqirilmaydi,
  // ya'ni `params` tozalanmaydi — to'g'ridan-to'g'ri to'ldirsak bo'ladi.
  draft.params
    ..clear()
    ..addAll(l.params);

  draft.transaction
    ..saleType = l.saleType
    ..ownershipYears = l.ownershipYears
    ..ownersCount = l.ownersCount
    ..registeredCount = l.registeredCount;

  draft.price
    ..mortgage = l.mortgage
    ..amount = _numStr(l.priceAmount)
    ..unit = unitFromCurrency(l.priceCurrency, l.pricePeriod)
    ..negotiable = l.negotiable
    ..dailyAmount = l.dailyAmount == null ? '' : _numStr(l.dailyAmount)
    ..dailyUnit = (l.dailyCurrency ?? '').isEmpty ? 'UZS' : l.dailyCurrency!;

  draft.description
    ..text = l.description ?? ''
    ..youtubeUrl = l.youtubeUrl ?? '';
  // Mavjud fayllar KALIT bilan olinadi: `PATCH` media ro'yxatini to'liq
  // almashtiradi, ya'ni ularni qaytarib yubormasak e'lon rasmsiz qolardi.
  // Kalit bo'sh bo'lsa (bayroqdan oldingi server) o'sha faylni ro'yxatga
  // qo'shmaymiz — noto'g'ri kalit yuborish 400 berardi.
  // Mavjud tur — KALITLAR bilan keladi va shundayligicha qaytariladi.
  // Busiz e'lonni tahrirlash (masalan matnni tuzatish) turni JIMGINA
  // o'chirib tashlardi: `PATCH` media'ni almashtiradi, server esa
  // almashtirilgan media bilan birga kelmagan havolalarni tozalaydi.
  draft.description.tourLinks
    ..clear()
    ..addAll(l.tour);
  draft.description.existingMedia
    ..clear()
    ..addAll([
      for (final m in l.media)
        if (m.storageKey.isNotEmpty)
          ExistingMedia(
            key: m.storageKey,
            role: m.role,
            sortOrder: m.sortOrder,
            isCover: m.isCover,
            title: m.title,
          ),
    ]);
  // Tahrirlashda xona nomlari sehrgar ro'yxatida ko'rinsin.
  draft.description.panoramaNames
    ..clear()
    ..addAll({
      for (final m in l.media)
        if (m.role == 'panorama' && (m.title ?? '').trim().isNotEmpty)
          m.storageKey: m.title!.trim(),
    });

  draft.contacts
    ..name = l.contactName
    ..email = l.contactEmail ?? '';
  draft.contacts.phones
    ..clear()
    ..addAll(l.contactPhones.isEmpty ? [l.contactPhone] : l.contactPhones);

  // Rozilik qaytadan belgilanadi — tahrirlash ham yuborish (reja Z5).
  draft.terms.accepted = false;

  return draft;
}

/// Tahrirlash uchun `PATCH` tanasi.
///
/// [draftToPayload] dan farqi ikkita:
///   * `deal_type`/`property_kind`/`property_type` YUBORILMAYDI —
///     `ListingUpdateRequest` da bu maydonlar YO'Q (mulk turini o'zgartirish
///     butun `params` sxemasini buzardi);
///   * [media] bo'sh bo'lsa `description.media` UMUMAN yuborilmaydi, ya'ni
///     server rasmlarga TEGMAYDI (`DescriptionUpdateIn.media = None`).
///     Bo'sh ro'yxat yuborish server uchun "hammasini o'chir" degani bo'lardi.
Map<String, dynamic> draftToUpdatePayload(
  BozorDraft draft,
  List<Map<String, Object?>> media,
) {
  final full = draftToPayload(draft, media);
  final description = <String, Object?>{
    if (draft.description.text.trim().isNotEmpty)
      'text': draft.description.text.trim(),
    if (draft.description.youtubeUrl.isNotEmpty)
      'youtube_url': draft.description.youtubeUrl,
    if (media.isNotEmpty) 'media': media,
    // ⚠️ `media` bilan BIRGA yuriladi. Server turni faqat media
    // almashtirilganda qayta bog'laydi (`media is not None`), ya'ni
    // media'siz yuborilgan tur JIMGINA e'tiborsiz qolardi — va
    // foydalanuvchi qo'ygan tugma saqlanmadi deb o'ylardi.
    if (media.isNotEmpty)
      'tour': (full['description']! as Map<String, Object?>)['tour'],
  };
  return {
    'title': full['title'],
    'address': full['address'],
    'params': full['params'],
    // Ijara e'lonida `draftToPayload` bu kalitni umuman yozmaydi, ya'ni
    // `PATCH` ham uni yubormaydi va server «Сделка» ga tegmaydi.
    if (full.containsKey('deal')) 'deal': full['deal'],
    'price': full['price'],
    'description': description,
    'contacts': full['contacts'],
  };
}
