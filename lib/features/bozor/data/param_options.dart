/// 3-qadamdagi tanlov ro'yxatlari — backenddan.
///
/// Manba: `GET /api/v1/listings/options?locale=` → `{lists: {ro'yxat: [{code,
/// label}]}}`. Yorliqlar `app_translations` dagi `listing.option.*` kalitlari
/// (adminkadan tahrirlanadi), kodlar esa `app/schemas/listing_options.py` da.
///
/// ⚠️ QIYMAT SIFATIDA KOD SAQLANADI, yorliq emas. Ilgari bu yerda qo'lda
/// yozilgan o'zbekcha ro'yxat bor edi va uning matni to'g'ridan-to'g'ri
/// qiymat bo'lardi — shu sababli shartli maydonlar (`parking == 'Garaj'`)
/// faqat bitta tilda ishlardi va server ham bunday qiymatni rad etadi.
library;

import 'bozor_api.dart';

abstract class ParamOptionsRepository {
  const ParamOptionsRepository();

  /// Ro'yxat kalitiga qarab variantlar. Noma'lum kalit — bo'sh ro'yxat.
  Future<List<ListingOption>> options(String key);
}

/// Barcha ro'yxatlarni BITTA so'rovda oladi va eslab qoladi: bitta formada
/// o'ntagacha select bor, har biriga alohida so'rov ketishi kerak emas.
class ApiParamOptions extends ParamOptionsRepository {
  ApiParamOptions({required this.locale, BozorApi? api})
    : _api = api ?? BozorApi();

  final String locale;
  final BozorApi _api;

  Map<String, List<ListingOption>>? _cache;
  Future<Map<String, List<ListingOption>>>? _inflight;

  Future<Map<String, List<ListingOption>>> _load() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    // Bir vaqtda bir nechta maydon so'rasa ham so'rov BITTA bo'ladi.
    return _inflight ??= _api.options(locale).then((v) {
      _cache = v;
      _inflight = null;
      return v;
    }, onError: (Object e) {
      _inflight = null;
      throw e;
    });
  }

  @override
  Future<List<ListingOption>> options(String key) async =>
      (await _load())[key] ?? const [];
}
