/// Testlarda 3-qadam sxemasini yuklaydi.
///
/// Sxema endi ilovada QOTIB yozilmagan — u backenddan keladi va ishga
/// tushganda `ListingParamSchema.instance.load()` bilan o'qiladi
/// (`lib/features/bozor/data/listing_param_schema_store.dart`). Testda
/// `main()` ishlamaydi, shuning uchun sxemani shu yerda qo'lda qo'yamiz.
///
/// Manba — ilova ichidagi haqiqiy nusxa (`assets/listing_param_schema.json`),
/// qo'lda yozilgan soxta ro'yxat emas: aks holda testlar prodda bo'lmagan
/// maydonlar bilan yashil bo'lib turardi.
library;

import 'dart:convert';
import 'dart:io';

import 'package:kadastr/features/bozor/data/listing_param_schema_store.dart';
import 'package:kadastr/features/bozor/models/param_schema.dart';

const String kParamSchemaAsset = 'assets/listing_param_schema.json';

/// `setUpAll(loadRealParamSchema)` deb chaqiriladi.
void loadRealParamSchema() {
  final raw = File(kParamSchemaAsset).readAsStringSync();
  ListingParamSchema.instance.debugSet(
    ListingParamSchemaDoc.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    ),
  );
}
