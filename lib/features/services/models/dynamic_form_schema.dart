/// Backend'dan keladigan dinamik forma sxemasi (form builder).
///
/// `GET /forms/{key}` qaytaradigan JSON shu modelga parse qilinadi. Wizard va
/// ariza detali shu sxema bo'yicha generik renderlaydi; javoblar `field.mapsTo`
/// (nuqtali yo'l) orqali mavjud submit payload shakliga moslanadi.
library;

import 'package:flutter/widgets.dart' show Locale;

String trMap(Map<String, dynamic>? m, Locale locale) {
  if (m == null || m.isEmpty) return '';
  final lang = locale.languageCode;
  return (m[lang] ?? m['uz'] ?? m['ru'] ?? m['en'] ?? m.values.first).toString();
}

enum FormFieldType {
  text,
  textarea,
  number,
  integer,
  toggle,
  singleChoice,
  multiChoice,
  date,
  rooms,
  note,
  unknown;

  static FormFieldType parse(String? raw) => switch (raw) {
        'text' => text,
        'textarea' => textarea,
        'number' => number,
        'integer' => integer,
        'toggle' => toggle,
        'single_choice' => singleChoice,
        'multi_choice' => multiChoice,
        'date' => date,
        'rooms' => rooms,
        'note' => note,
        _ => unknown,
      };
}

class FormOption {
  const FormOption({required this.value, required this.label});

  final String value;
  final Map<String, dynamic> label;

  factory FormOption.fromJson(Map<String, dynamic> j) => FormOption(
        value: j['value'].toString(),
        label: (j['label'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

class FormFieldDef {
  const FormFieldDef({
    required this.key,
    required this.label,
    required this.type,
    required this.mapsTo,
    this.required = false,
    this.core = false,
    this.unit,
    this.placeholder,
    this.help,
    this.min,
    this.max,
    this.defaultValue,
    this.options = const [],
  });

  final String key;
  final Map<String, dynamic> label;
  final FormFieldType type;

  /// Submit payload'idagi nuqtali yo'l (masalan, "object_type" yoki
  /// "details.architecture.style"). Bo'sh bo'lsa — javob faqat ko'rsatiladi.
  final String mapsTo;
  final bool required;
  final bool core;
  final String? unit;
  final Map<String, dynamic>? placeholder;
  final Map<String, dynamic>? help;
  final num? min;
  final num? max;
  final dynamic defaultValue;
  final List<FormOption> options;

  factory FormFieldDef.fromJson(Map<String, dynamic> j) => FormFieldDef(
        key: j['key'].toString(),
        label: (j['label'] as Map?)?.cast<String, dynamic>() ?? {},
        type: FormFieldType.parse(j['type'] as String?),
        mapsTo: (j['maps_to'] ?? '').toString(),
        required: j['required'] == true,
        core: j['core'] == true,
        unit: j['unit'] as String?,
        placeholder: (j['placeholder'] as Map?)?.cast<String, dynamic>(),
        help: (j['help'] as Map?)?.cast<String, dynamic>(),
        min: j['min'] as num?,
        max: j['max'] as num?,
        defaultValue: j['default'],
        options: ((j['options'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => FormOption.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
      );
}

class FormSectionDef {
  const FormSectionDef({
    required this.key,
    required this.title,
    this.help,
    this.fields = const [],
  });

  final String key;
  final Map<String, dynamic> title;
  final Map<String, dynamic>? help;
  final List<FormFieldDef> fields;

  factory FormSectionDef.fromJson(Map<String, dynamic> j) => FormSectionDef(
        key: (j['key'] ?? '').toString(),
        title: (j['title'] as Map?)?.cast<String, dynamic>() ?? {},
        help: (j['help'] as Map?)?.cast<String, dynamic>(),
        fields: ((j['fields'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => FormFieldDef.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false),
      );
}

class FormSchema {
  const FormSchema({
    required this.key,
    required this.title,
    this.subtitle,
    this.version = 1,
    this.sections = const [],
  });

  final String key;
  final Map<String, dynamic> title;
  final Map<String, dynamic>? subtitle;
  final int version;
  final List<FormSectionDef> sections;

  factory FormSchema.fromJson(Map<String, dynamic> j) {
    final schema = (j['schema'] as Map?)?.cast<String, dynamic>() ?? const {};
    return FormSchema(
      key: (j['key'] ?? '').toString(),
      title: (j['title'] as Map?)?.cast<String, dynamic>() ?? {},
      subtitle: (j['subtitle'] as Map?)?.cast<String, dynamic>(),
      version: (j['version'] as num?)?.toInt() ?? 1,
      sections: ((schema['sections'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => FormSectionDef.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  /// Barcha maydonlar (bo'limlar bo'ylab tekis) — payload mapping/detail uchun.
  Iterable<FormFieldDef> get allFields =>
      sections.expand((s) => s.fields);
}
