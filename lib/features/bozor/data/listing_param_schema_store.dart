/// E'lon sehrgarining 3-qadam sxemasini SAQLAB turuvchi do'kon.
///
/// Sxema backenddan keladi (`GET /api/v1/listings/schema`), lekin wizard uni
/// SINXRON o'qishi kerak: `type.paramFields` widget qurilayotganda chaqiriladi.
/// Shuning uchun `AppTranslationsStore` bilan bir xil naqsh:
///
///   1. ilova ichidagi nusxa (`assets/listing_param_schema.json`) — tarmoqsiz
///      birinchi ochilishda ham sehrgar ishlaydi;
///   2. keshlangan javob (`SharedPreferences`) — oldingi seansdan;
///   3. fonda yangisi so'raladi va keshga yoziladi.
///
/// ⚠️ YANGI SXEMA KEYINGI SEANSDA QO'LLANADI, oqim o'rtasida emas: maydonlar
/// to'plami wizard ochiq turganda o'zgarsa, foydalanuvchi to'ldirgan qiymatlar
/// birdan "notanish parametr" bo'lib qolishi mumkin edi.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/param_schema.dart';
import 'bozor_api.dart';

const String _assetPath = 'assets/listing_param_schema.json';
const String _prefsKey = 'bozor_param_schema_v1';

class ListingParamSchema {
  ListingParamSchema._();

  static final ListingParamSchema instance = ListingParamSchema._();

  ListingParamSchemaDoc _doc = const ListingParamSchemaDoc(
    version: 0,
    types: {},
  );

  /// Hozirgi sxema. [load] chaqirilmagan bo'lsa bo'sh — ya'ni hech bir turda
  /// parametr yo'q. Shuning uchun [load] `main()` da, sehrgar ochilishidan
  /// oldin chaqiriladi.
  ListingParamSchemaDoc get doc => _doc;

  List<ParamField> fieldsFor(String? typeCode) => _doc.fieldsFor(typeCode);

  /// Testlar uchun: sxemani qo'lda qo'yish.
  void debugSet(ListingParamSchemaDoc doc) => _doc = doc;

  /// Ilova ishga tushganda: keshdan (yoki ilova ichidagi nusxadan) o'qiydi va
  /// fonda yangilanishni boshlaydi.
  Future<void> load({BozorApi? api}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    var applied = false;
    if (cached != null) {
      applied = _apply(cached);
    }
    if (!applied) {
      // Kesh yo'q yoki buzilgan — ilova ichidagi nusxa.
      try {
        _apply(await rootBundle.loadString(_assetPath));
      } catch (_) {
        // Asset ham o'qilmasa sxema bo'sh qoladi; sehrgar 3-qadamsiz
        // ishlaydi. Bu ilovani yiqitishdan ko'ra yaxshiroq.
      }
    }
    // Fon yangilanishi — javobni KUTMAYMIZ.
    unawaitedRefresh(api: api);
  }

  /// Fonda yangi sxemani oladi. Xato bo'lsa jim qoladi: eski sxema ishlaydi.
  void unawaitedRefresh({BozorApi? api}) {
    () async {
      try {
        final body = await (api ?? BozorApi()).paramSchema();
        final text = jsonEncode(body);
        final next = ListingParamSchemaDoc.fromJson(body);
        // ⚠️ VERSIYA BO'YICHA FILTRLAMAYMIZ. Avval bu yerda
        // `if (next.version < _doc.version) return;` turardi — "eski javob
        // kelib qolmasin" degan o'y bilan. Lekin oqibati boshqa: serverda
        // sxema ORQAGA qaytarilsa (yomon o'zgarish bekor qilinsa), ilova uni
        // BUTUNLAY qabul qilmay qo'yardi, chunki keshdagi versiya kattaroq.
        // Server — yagona manba; nima bersa, o'sha.
        if (next.types.isEmpty) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, text);
        // Xotiradagisi ham yangilanadi: sehrgar hali ochilmagan bo'lsa yangi
        // sxemani darrov oladi.
        _doc = next;
      } catch (_) {
        // Tarmoq yo'q / server yiqilgan — jim o'tamiz.
      }
    }();
  }

  bool _apply(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map) return false;
      final doc = ListingParamSchemaDoc.fromJson(Map<String, dynamic>.from(j));
      if (doc.types.isEmpty) return false;
      _doc = doc;
      return true;
    } catch (_) {
      return false;
    }
  }
}
