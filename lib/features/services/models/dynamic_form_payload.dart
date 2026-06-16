/// Dinamik forma javoblari ↔ submit payload o'zaro moslash.
///
/// Har bir maydonning `mapsTo` qiymati payload ichidagi nuqtali yo'l
/// ("object_type" yoki "details.architecture.style"). Shu sbabli generik
/// renderer javoblarni mavjud backend submit shakliga aynan moslaydi — backend
/// o'zgarmaydi. Detal ekrani teskari yo'nalishda o'qiydi.
library;

import 'dynamic_form_schema.dart';

/// Nuqtali yo'l bo'yicha [root] ichiga [value] yozadi (oraliq map'larni yaratib).
void setByPath(Map<String, dynamic> root, String path, dynamic value) {
  if (path.isEmpty) return;
  final parts = path.split('.');
  Map<String, dynamic> node = root;
  for (var i = 0; i < parts.length - 1; i++) {
    final p = parts[i];
    final next = node[p];
    if (next is Map<String, dynamic>) {
      node = next;
    } else {
      final created = <String, dynamic>{};
      node[p] = created;
      node = created;
    }
  }
  node[parts.last] = value;
}

/// Nuqtali yo'l bo'yicha [root] dan qiymatni o'qiydi (topilmasa null).
dynamic getByPath(Map<String, dynamic> root, String path) {
  if (path.isEmpty) return null;
  dynamic node = root;
  for (final p in path.split('.')) {
    if (node is Map && node.containsKey(p)) {
      node = node[p];
    } else {
      return null;
    }
  }
  return node;
}

/// Javoblardan ([answers] — field.key → qiymat) submit payload quradi.
/// Bo'sh/null qiymatlar tashlanadi (toggle'lar bundan mustasno — bool yuboriladi).
Map<String, dynamic> buildPayload(FormSchema schema, Map<String, dynamic> answers) {
  final payload = <String, dynamic>{};
  for (final field in schema.allFields) {
    if (field.mapsTo.isEmpty) continue;
    final v = answers[field.key];
    final isBool = field.type == FormFieldType.toggle;
    final isEmpty = v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty);
    if (isEmpty && !isBool) continue;
    setByPath(payload, field.mapsTo, isBool ? (v == true) : v);
  }
  return payload;
}
