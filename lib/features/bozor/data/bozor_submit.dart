/// Qoralamani backendga yuborish.
///
/// Ikki bosqich: avval fayllar yuklanadi (`POST /listings/media`), keyin
/// e'lonning o'zi (`POST /listings/`) — yuklash kalitlari bilan.
///
/// Nega alohida fayl: 7-qadam ekrani UI bilan band, bu yerda esa tarmoq
/// ketma-ketligi va xatolar. Ikkalasi bir joyda bo'lsa ekran o'qib
/// bo'lmaydigan bo'lib ketardi.
library;

import '../models/bozor_draft.dart';
import 'bozor_api.dart';

/// Yuklash jarayonining holati — ekran progress ko'rsatishi uchun.
typedef SubmitProgress = void Function(int done, int total);

class BozorSubmitter {
  BozorSubmitter({BozorApi? api}) : _api = api ?? BozorApi();

  final BozorApi _api;

  /// Qoralamani yuboradi va yaratilgan e'lonni qaytaradi.
  ///
  /// Xatolikda [BozorApiException] tashlaydi — ekran uni foydalanuvchiga
  /// ko'rsatadi va qoralama JOYIDA qoladi, ya'ni qayta urinish mumkin.
  Future<Map<String, dynamic>> submit(
    BozorDraft draft, {
    SubmitProgress? onProgress,
  }) async {
    final d = draft.description;

    // ── 1. Fayllar ────────────────────────────────────────────────────────
    // Rollar bo'yicha alohida so'rov: backend `role` ni forma maydonida
    // kutadi va har rolning o'z chegarasi bor.
    final groups = <String, List<String>>{
      'photo': d.photos,
      'plan': d.planFiles,
      'panorama': d.panoramas,
    }..removeWhere((_, v) => v.isEmpty);

    final total = groups.length + 1; // + e'lonning o'zi
    var done = 0;
    void tick() => onProgress?.call(++done, total);

    final media = <Map<String, Object?>>[];
    for (final entry in groups.entries) {
      final uploaded = await _api.uploadMedia(
        role: entry.key,
        paths: entry.value,
      );
      for (var i = 0; i < uploaded.length; i++) {
        media.add({
          'key': uploaded[i].key,
          'role': entry.key,
          'sort_order': i,
          // Muqova — birinchi foto. Backend ham shu qoidaga tushadi, lekin
          // aniq aytib qo'ygan yaxshi.
          'is_cover': entry.key == 'photo' && i == 0,
        });
      }
      tick();
    }

    // ── 2. E'lon ──────────────────────────────────────────────────────────
    final payload = buildPayload(draft, media);
    final created = await _api.createListing(payload);
    tick();
    return created;
  }

  /// So'rov tanasi. Ochiq — testda tekshirish uchun.
  static Map<String, dynamic> buildPayload(
    BozorDraft draft,
    List<Map<String, Object?>> media,
  ) {
    final a = draft.address;
    final p = draft.price;
    final d = draft.description;
    final c = draft.contacts;

    return {
      'deal_type': draft.deal!.code,
      'property_kind': draft.kind!.code,
      'property_type': draft.type!.code,
      'title': draft.title,
      'address': {
        'region_id': a.regionId,
        'district_id': a.districtId,
        'address': a.address,
        if (a.landmark.isNotEmpty) 'landmark': a.landmark,
        if (a.apartmentNumber.isNotEmpty)
          'apartment_number': a.apartmentNumber,
        if (a.entrance.isNotEmpty) 'entrance': a.entrance,
        if (a.houseNumber.isNotEmpty) 'house_number': a.houseNumber,
        if (a.floor.isNotEmpty) 'floor': int.tryParse(a.floor),
        if (a.totalFloors.isNotEmpty) 'total_floors': int.tryParse(a.totalFloors),
        if (a.lat != null) 'lat': a.lat,
        if (a.lng != null) 'lng': a.lng,
      },
      'params': draft.params,
      'price': {
        'amount': num.tryParse(p.amount) ?? 0,
        'currency': _currencyOf(p.unit),
        'period': _periodOf(p.unit),
        'negotiable': p.negotiable,
        if (p.dailyAmount.isNotEmpty) ...{
          'daily_amount': num.tryParse(p.dailyAmount),
          'daily_currency': _currencyOf(p.dailyUnit),
        },
      },
      'description': {
        if (d.text.trim().isNotEmpty) 'text': d.text.trim(),
        if (d.youtubeUrl.isNotEmpty) 'youtube_url': d.youtubeUrl,
        'media': media,
      },
      'contacts': {
        'name': c.name,
        'phones': c.phones.where((s) => s.isNotEmpty).toList(),
        if (c.email.isNotEmpty) 'email': c.email,
      },
      'terms': {
        'tier': draft.terms.tier.code,
        'accepted': draft.terms.accepted,
      },
    };
  }

  /// `UZS/oy` → `UZS`.
  static String _currencyOf(String unit) => unit.split('/').first.trim();

  /// `UZS/oy` → `month`; davrsiz token → `null`.
  static String? _periodOf(String unit) {
    if (!unit.contains('/')) return null;
    final suffix = unit.split('/').last.trim().toLowerCase();
    return switch (suffix) {
      'oy' || 'мес' || 'mo' => 'month',
      'kun' || 'сут' || 'day' => 'day',
      _ => null,
    };
  }

  void dispose() => _api.dispose();
}

// Enumlarni backend kodlariga o'giradigan kengaytmalar. Nomlar
// `app/schemas/listing_options.py` bilan AYNAN bir xil.
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

extension PropertyTypeCode on PropertyType {
  String get code => switch (this) {
    PropertyType.apartment => 'apartment',
    PropertyType.house => 'house',
    PropertyType.land => 'land',
    PropertyType.commercial => 'commercial',
    PropertyType.garage => 'garage',
    PropertyType.otherNonResidential => 'other_non_residential',
  };
}

extension PlacementTierCode on PlacementTier {
  String get code => switch (this) {
    PlacementTier.standard => 'standard',
    PlacementTier.top => 'top',
  };
}
