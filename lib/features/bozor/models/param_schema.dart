/// 3-qadam (`Параметры`) sxemasi.
///
/// Beshta mulk turida butunlay boshqa maydonlar to'plami bor, ustiga har
/// biriga "Barcha parametrlar" to'liq ekrani. Ularni beshta ekran qilib
/// yozish o'rniga BITTA jadval + bitta renderer: yangi maydon qo'shish =
/// shu faylga bitta qator qo'shish.
///
/// Har bir maydon [ParamField]. `inStep` — 3/7 ekranida ham ko'rinadimi;
/// qolganlari faqat "Barcha parametrlar" ekranida. `visibleWhen` — boshqa
/// maydon qiymatiga bog'liq qatorlar (pristroyka, uchastka, biznes-markaz,
/// garaj bloki).
library;

import 'bozor_draft.dart';

enum ParamControl { number, integer, text, select, multiSelect, toggle }

/// "Barcha parametrlar" ekranidagi ikkita bo'lim.
enum ParamSection { main, extra }

typedef ParamValues = Map<String, Object?>;

class ParamField {
  const ParamField({
    required this.key,
    required this.control,
    this.unit,
    this.optional = false,
    this.inStep = false,
    this.section = ParamSection.main,
    this.optionsKey,
    this.visibleWhen,
  });

  /// Qoralamadagi kalit va tarjima kaliti asosi: `bozor.param.<key>`.
  final String key;
  final ParamControl control;

  /// Maydon ichidagi o'lchov birligi (`m²`, `sot.`, `m`, `y`). Faqat ko'rinish.
  final String? unit;

  /// Dizaynda `(по желанию)` bilan belgilangan — bizda `*` qo'yilmaydi.
  final bool optional;

  /// 3/7 ekranida ham chiziladimi.
  final bool inStep;

  final ParamSection section;

  /// `ParamOptions` dagi ro'yxat kaliti. select/multiSelect uchun shart.
  final String? optionsKey;

  /// Boshqa maydonga bog'liq ko'rinish. `null` — doim ko'rinadi.
  final bool Function(ParamValues values)? visibleWhen;

  String get labelKey => 'bozor.param.$key';
}

// ── Shartlar ────────────────────────────────────────────────────────────────
bool _on(ParamValues v, String key) => v[key] == true;

/// Garaj kichik bloki kvartira varag'ida `Парковка = Гараж` bo'lgandagina
/// chiqadi.
///
/// ⚠️ KOD bo'yicha solishtiriladi, YORLIQ bo'yicha emas. Ilgari bu yerda
/// `== 'Garaj'` turardi va u faqat o'zbek tilida ishlardi: boshqa tilda
/// qiymat boshqa matn bo'lgani uchun garaj bloki jimgina ochilmay qolardi.
/// Kodlar backenddagi `app/schemas/listing_options.py` bilan bir xil.
bool _garageParking(ParamValues v) => v['parking'] == 'garage';

bool _businessCentre(ParamValues v) => v['building_type'] == 'business_center';

// ── Umumiy maydonlar (bir nechta turda takrorlanadi) ────────────────────────
const _electricity = ParamField(
  key: 'electricity',
  control: ParamControl.toggle,
);
const _water = ParamField(key: 'water_supply', control: ParamControl.toggle);
const _gas = ParamField(key: 'gas', control: ParamControl.toggle);
const _sewerage = ParamField(key: 'sewerage', control: ParamControl.toggle);

const _security = ParamField(
  key: 'security',
  control: ParamControl.multiSelect,
  optional: true,
  section: ParamSection.extra,
  optionsKey: 'security',
);
const _amenities = ParamField(
  key: 'amenities',
  control: ParamControl.multiSelect,
  optional: true,
  section: ParamSection.extra,
  optionsKey: 'amenities',
);
const _yard = ParamField(
  key: 'yard_improvements',
  control: ParamControl.multiSelect,
  optional: true,
  section: ParamSection.extra,
  optionsKey: 'yard_improvements',
);
const _infrastructure = ParamField(
  key: 'infrastructure',
  control: ParamControl.multiSelect,
  optional: true,
  section: ParamSection.extra,
  optionsKey: 'infrastructure',
);

// ── Kvartira ────────────────────────────────────────────────────────────────
const _apartment = <ParamField>[
  ParamField(
    key: 'rooms_count',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'rooms_count',
  ),
  ParamField(
    key: 'total_area',
    control: ParamControl.number,
    unit: 'm²',
    inStep: true,
  ),
  ParamField(key: 'living_area', control: ParamControl.number, unit: 'm²'),
  ParamField(
    key: 'kitchen_area',
    control: ParamControl.number,
    unit: 'm²',
    optional: true,
  ),
  ParamField(
    key: 'ceiling_height',
    control: ParamControl.number,
    unit: 'm',
    optional: true,
  ),
  ParamField(
    key: 'bathroom',
    control: ParamControl.select,
    optional: true,
    optionsKey: 'bathroom',
  ),
  ParamField(
    key: 'balcony',
    control: ParamControl.select,
    optional: true,
    optionsKey: 'balcony',
  ),
  ParamField(
    key: 'renovation',
    control: ParamControl.select,
    optional: true,
    optionsKey: 'renovation',
  ),
  ParamField(
    key: 'window_view',
    control: ParamControl.multiSelect,
    optional: true,
    optionsKey: 'window_view',
  ),
  ParamField(
    key: 'build_year',
    control: ParamControl.integer,
    unit: 'y',
    optional: true,
  ),
  ParamField(
    key: 'elevator',
    control: ParamControl.select,
    optional: true,
    optionsKey: 'elevator',
  ),
  ParamField(key: 'freight_elevator', control: ParamControl.toggle),
  _gas,
  // Dополнительные
  ParamField(
    key: 'parking',
    control: ParamControl.select,
    section: ParamSection.extra,
    optionsKey: 'parking',
  ),
  // Garaj kichik bloki — faqat `Парковка = Гараж` bo'lganda.
  ParamField(
    key: 'garage_ceiling_height',
    control: ParamControl.number,
    unit: 'm',
    optional: true,
    section: ParamSection.extra,
    visibleWhen: _garageParking,
  ),
  ParamField(
    key: 'garage_material',
    control: ParamControl.multiSelect,
    optional: true,
    section: ParamSection.extra,
    optionsKey: 'garage_material',
    visibleWhen: _garageParking,
  ),
  ParamField(
    key: 'garage_status',
    control: ParamControl.multiSelect,
    optional: true,
    section: ParamSection.extra,
    optionsKey: 'garage_status',
    visibleWhen: _garageParking,
  ),
  ParamField(
    key: 'gsk_name',
    control: ParamControl.text,
    optional: true,
    section: ParamSection.extra,
    visibleWhen: _garageParking,
  ),
  ParamField(
    key: 'garage_area',
    control: ParamControl.number,
    unit: 'm²',
    section: ParamSection.extra,
    visibleWhen: _garageParking,
  ),
  ParamField(
    key: 'garage_security',
    control: ParamControl.multiSelect,
    section: ParamSection.extra,
    optionsKey: 'garage_security',
    visibleWhen: _garageParking,
  ),
  ParamField(
    key: 'garage_amenities',
    control: ParamControl.multiSelect,
    section: ParamSection.extra,
    optionsKey: 'garage_amenities',
    visibleWhen: _garageParking,
  ),
  _security,
  _amenities,
  _yard,
  _infrastructure,
];

// ── Uy ──────────────────────────────────────────────────────────────────────
const _house = <ParamField>[
  ParamField(
    key: 'land_area',
    control: ParamControl.number,
    unit: 'sot.',
    inStep: true,
  ),
  ParamField(
    key: 'land_type',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'land_type',
  ),
  ParamField(key: 'electricity', control: ParamControl.toggle, inStep: true),
  ParamField(key: 'water_supply', control: ParamControl.toggle, inStep: true),
  ParamField(key: 'gas', control: ParamControl.toggle, inStep: true),
  ParamField(key: 'sewerage', control: ParamControl.toggle, inStep: true),
  ParamField(
    key: 'house_area',
    control: ParamControl.number,
    unit: 'm²',
    inStep: true,
  ),
  ParamField(
    key: 'rooms_count',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'rooms_count',
  ),
  ParamField(
    key: 'house_type',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'house_type',
  ),
  ParamField(
    key: 'irrigated_area',
    control: ParamControl.number,
    unit: 'm²',
    optional: true,
  ),
  ParamField(
    key: 'built_up_area',
    control: ParamControl.number,
    unit: 'm²',
    optional: true,
  ),
  ParamField(
    key: 'living_area',
    control: ParamControl.number,
    unit: 'm²',
    optional: true,
  ),
  ParamField(
    key: 'ceiling_height',
    control: ParamControl.number,
    unit: 'm',
    optional: true,
  ),
  ParamField(
    key: 'bathroom_location',
    control: ParamControl.select,
    optional: true,
    optionsKey: 'bathroom_location',
  ),
  ParamField(
    key: 'bathroom_type',
    control: ParamControl.select,
    optionsKey: 'bathroom',
  ),
  ParamField(
    key: 'renovation',
    control: ParamControl.select,
    optional: true,
    optionsKey: 'renovation',
  ),
  _security,
  _amenities,
  _yard,
  _infrastructure,
];

// ── Yer uchastkasi ──────────────────────────────────────────────────────────
const _land = <ParamField>[
  ParamField(
    key: 'land_area',
    control: ParamControl.number,
    unit: 'sot.',
    inStep: true,
  ),
  ParamField(
    key: 'land_type',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'land_type',
  ),
  ParamField(key: 'has_annex', control: ParamControl.toggle, inStep: true),
  ParamField(
    key: 'annex_area',
    control: ParamControl.number,
    unit: 'm²',
    inStep: true,
    visibleWhen: _hasAnnex,
  ),
  ParamField(
    key: 'rooms_count',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'rooms_count',
  ),
  _electricity,
  _water,
  _gas,
  _sewerage,
  _amenities,
  _infrastructure,
];

bool _hasAnnex(ParamValues v) => _on(v, 'has_annex');
bool _withLand(ParamValues v) => _on(v, 'with_land');

// ── Tijorat obyekti ─────────────────────────────────────────────────────────
const _commercial = <ParamField>[
  ParamField(
    key: 'purpose',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'purpose',
  ),
  ParamField(
    key: 'building_type',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'building_type',
  ),
  ParamField(
    key: 'premises_area',
    control: ParamControl.number,
    unit: 'm²',
    inStep: true,
  ),
  ParamField(key: 'with_land', control: ParamControl.toggle, inStep: true),
  ParamField(
    key: 'land_area',
    control: ParamControl.number,
    unit: 'm²',
    inStep: true,
    visibleWhen: _withLand,
  ),
  ParamField(
    key: 'business_center_name',
    control: ParamControl.text,
    visibleWhen: _businessCentre,
  ),
  ParamField(key: 'building_floors', control: ParamControl.integer),
  ParamField(key: 'whole_building', control: ParamControl.toggle),
  ParamField(key: 'floor', control: ParamControl.integer),
  ParamField(
    key: 'possible_purpose',
    control: ParamControl.select,
    optionsKey: 'purpose',
  ),
  ParamField(
    key: 'rooms_count',
    control: ParamControl.select,
    optionsKey: 'rooms_count',
  ),
  ParamField(
    key: 'entrance_kind',
    control: ParamControl.select,
    optionsKey: 'entrance_kind',
  ),
  ParamField(
    key: 'renovation',
    control: ParamControl.select,
    optionsKey: 'renovation',
  ),
  _electricity,
  _water,
  _gas,
  _sewerage,
  ParamField(
    key: 'bathrooms_count',
    control: ParamControl.select,
    optional: true,
    optionsKey: 'rooms_count',
  ),
  _security,
  _amenities,
  _infrastructure,
];

// ── Garaj / parkovka ────────────────────────────────────────────────────────
// DIQQAT: bu turda "Barcha parametrlar" varag'i dizaynda YO'Q — hamma maydon
// 3/7 ekranining o'zida. Shu sababli `inStep: true` va navigatsiya qatori
// chizilmaydi ([PropertyTypeParamsX.hasAllParamsScreen]).
const _garage = <ParamField>[
  ParamField(
    key: 'garage_kind',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'garage_kind',
  ),
  ParamField(
    key: 'parking_type',
    control: ParamControl.select,
    inStep: true,
    optionsKey: 'parking_type',
  ),
  ParamField(
    key: 'garage_ceiling_height',
    control: ParamControl.number,
    unit: 'm',
    inStep: true,
  ),
  ParamField(
    key: 'garage_material',
    control: ParamControl.multiSelect,
    optional: true,
    inStep: true,
    optionsKey: 'garage_material',
  ),
  ParamField(
    key: 'garage_status',
    control: ParamControl.multiSelect,
    optional: true,
    inStep: true,
    optionsKey: 'garage_status',
  ),
  ParamField(
    key: 'gsk_name',
    control: ParamControl.text,
    optional: true,
    inStep: true,
  ),
  ParamField(
    key: 'garage_area',
    control: ParamControl.number,
    unit: 'm²',
    inStep: true,
  ),
  ParamField(
    key: 'garage_security',
    control: ParamControl.multiSelect,
    inStep: true,
    optionsKey: 'garage_security',
  ),
  ParamField(
    key: 'garage_amenities',
    control: ParamControl.multiSelect,
    inStep: true,
    optionsKey: 'garage_amenities',
  ),
];

extension PropertyTypeParamsX on PropertyType {
  /// Shu turdagi BARCHA parametrlar, chizish tartibida.
  List<ParamField> get paramFields => switch (this) {
    // Yangi bino kvartirasi — hozircha AYNAN oddiy kvartira maydonlari.
    // Dizaynda bu turning «Все параметры» jadvali ochilmagan (`1297-23722`
    // freymida oddiy kvartira maydonlari turibdi), ya'ni maxsus maydonlar
    // (застройщик, срок сдачи, очередь, тип отделки) TASDIQLANMAGAN.
    // Backend ham shu nusxani ishlatadi (`listing_param_schema.py`) — farq
    // kelganda ikkala tarafda ham faqat shu qator o'zgaradi.
    PropertyType.apartment || PropertyType.newBuildingApartment => _apartment,
    PropertyType.house => _house,
    PropertyType.land => _land,
    PropertyType.commercial => _commercial,
    PropertyType.garage => _garage,
    // "Boshqa noturar joy" da bu qadam umuman yo'q.
    PropertyType.otherNonResidential => const [],
  };

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
    fields.where((f) => f.visibleWhen?.call(values) ?? true).toList();
