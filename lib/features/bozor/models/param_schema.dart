/// 3-qadam (`Параметры`) sxemasi — BACKENDDAN keladi.
///
/// ⚠️ ILGARI SHU YERDA QOTIB YOZILGAN JADVAL TURARDI (~520 qator) va uning
/// aynan nusxasi backendda ham bor edi (`listing_param_schema.py`). Maydon
/// qo'shilsa ikkalasiga qo'shish kerak edi; unutilsa foydalanuvchi yetti
/// qadamni to'ldirib, oxirida tushunarsiz 400 olardi — 2026-09-10 da prodda
/// aynan shunday bo'ldi. Nusxani ikki tomonlama "parity" testi qo'riqlardi,
/// ya'ni muammo ma'lum edi, lekin yechilmagan: yangi mulk turi yoki maydon
/// HAR DOIM ilovaning yangi versiyasini talab qilardi.
///
/// 2026-09-23 dan beri manba bitta — `GET /api/v1/listings/schema`. Jadval
/// ilovada YO'Q; bu yerda faqat uni o'qiydigan model qoldi.
///
/// Yuklash tartibi [ListingParamSchema] da: ilova ichidagi nusxa (tarmoqsiz
/// birinchi ochilish uchun) → keshlangan javob → yangi javob.
library;

import '../data/listing_param_schema_store.dart';
import 'bozor_draft.dart';

enum ParamControl { number, integer, text, select, multiSelect, toggle }

/// "Barcha parametrlar" ekranidagi ikkita bo'lim.
enum ParamSection { main, extra }

typedef ParamValues = Map<String, Object?>;

/// Boshqa maydon qiymatiga bog'liq ko'rinish.
///
/// Ilgari bu Dart funksiyasi edi (`(v) => v['parking'] == 'garage'`), ya'ni
/// shartni faqat kod bilan yozish mumkin edi. Endi u MA'LUMOT: backend
/// `{"key": "parking", "value": "garage"}` yuboradi.
class ParamCondition {
  const ParamCondition({required this.key, required this.value});

  factory ParamCondition.fromJson(Map<String, dynamic> j) =>
      ParamCondition(key: j['key'] as String, value: j['value']);

  final String key;
  final Object? value;

  /// ⚠️ KOD bo'yicha solishtiriladi, YORLIQ bo'yicha emas. Ilgari bir joyda
  /// `== 'Garaj'` turardi va u faqat o'zbek tilida ishlardi: boshqa tilda
  /// qiymat boshqa matn bo'lgani uchun garaj bloki jimgina ochilmay qolardi.
  bool matches(ParamValues values) => values[key] == value;

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}

class ParamField {
  const ParamField({
    required this.key,
    required this.control,
    this.unit,
    this.optional = false,
    this.inStep = false,
    this.section = ParamSection.main,
    this.optionsKey,
    this.condition,
  });

  factory ParamField.fromJson(Map<String, dynamic> j) => ParamField(
    key: j['key'] as String,
    control: _controlFromWire(j['control'] as String?),
    unit: j['unit'] as String?,
    // Backend sukuti — «ixtiyoriy». Noma'lum maydonni MAJBURIY deb
    // hisoblasak, eski ilova yangi maydon tufayli qulflanib qolardi.
    optional: j['optional'] as bool? ?? true,
    inStep: j['in_step'] as bool? ?? false,
    section: j['section'] == 'extra' ? ParamSection.extra : ParamSection.main,
    optionsKey: j['options'] as String?,
    condition: j['visible_when'] == null
        ? null
        : ParamCondition.fromJson(
            Map<String, dynamic>.from(j['visible_when'] as Map),
          ),
  );

  /// Qoralamadagi kalit va tarjima kaliti asosi: `bozor.param.<key>`.
  final String key;
  final ParamControl control;

  /// Maydon ichidagi o'lchov birligi (`m²`, `sot.`, `m`, `y`). Faqat ko'rinish.
  ///
  /// (TUR, MAYDON) juftiga tegishli, maydonning o'ziga emas: `land_area`
  /// uyda `sot.`, yer uchastkasida esa `m²`.
  final String? unit;

  /// Dizaynda `(по желанию)` bilan belgilangan — bizda `*` qo'yilmaydi.
  final bool optional;

  /// 3/7 ekranida ham chiziladimi.
  final bool inStep;

  final ParamSection section;

  /// `ParamOptions` dagi ro'yxat kaliti. select/multiSelect uchun shart.
  final String? optionsKey;

  final ParamCondition? condition;

  String get labelKey => 'bozor.param.$key';

  bool isVisible(ParamValues values) => condition?.matches(values) ?? true;
}

/// Noma'lum `control` — matn maydoni. Ilova yiqilmaydi: backend yangi
/// kontrol turini qo'shsa, eski ilova uni hech bo'lmasa ko'rsatadi.
ParamControl _controlFromWire(String? wire) => switch (wire) {
  'number' => ParamControl.number,
  'integer' => ParamControl.integer,
  'select' => ParamControl.select,
  'multi_select' => ParamControl.multiSelect,
  'toggle' => ParamControl.toggle,
  _ => ParamControl.text,
};

/// Mulk turi (kod) → maydonlar.
class ListingParamSchemaDoc {
  const ListingParamSchemaDoc({required this.version, required this.types});

  factory ListingParamSchemaDoc.fromJson(Map<String, dynamic> j) {
    final types = <String, List<ParamField>>{};
    final raw = Map<String, dynamic>.from(j['types'] as Map? ?? const {});
    for (final e in raw.entries) {
      types[e.key] = [
        for (final f in (e.value as List))
          ParamField.fromJson(Map<String, dynamic>.from(f as Map)),
      ];
    }
    return ListingParamSchemaDoc(
      version: (j['version'] as num?)?.toInt() ?? 0,
      types: types,
    );
  }

  final int version;
  final Map<String, List<ParamField>> types;

  /// Noma'lum tur — bo'sh ro'yxat, ya'ni «parametrlar qadami yo'q».
  List<ParamField> fieldsFor(String? typeCode) =>
      typeCode == null ? const [] : (types[typeCode] ?? const []);
}

extension PropertyTypeParamsX on PropertyType {
  /// Shu turdagi BARCHA parametrlar, chizish tartibida.
  List<ParamField> get paramFields =>
      ListingParamSchema.instance.fieldsFor(code);

  /// 3/7 ekranida ko'rinadigan qisqa ro'yxat.
  List<ParamField> get stepParamFields =>
      paramFields.where((f) => f.inStep).toList();

  /// "Barcha parametrlar" ekrani bormi. Garajda hamma narsa qadamning
  /// o'zida — ochadigan narsa yo'q.
  bool get hasAllParamsScreen =>
      this != PropertyType.garage && paramFields.length > stepParamFields.length;
}

/// Ko'rinadigan maydonlarni filtrlaydi (shartlarni hisobga olib).
List<ParamField> visibleParams(List<ParamField> fields, ParamValues values) =>
    fields.where((f) => f.isVisible(values)).toList();


