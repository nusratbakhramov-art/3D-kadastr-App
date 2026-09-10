import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/bozor/models/bozor_draft.dart';
import 'package:kadastr/features/bozor/models/param_schema.dart';

/// `param_schema.dart` ↔ backend `listing_param_schema.py` PARITY qo'riqchisi.
///
/// SABAB (2026-09-10): foydalanuvchi prod'da `submit` dan 400 oldi —
/// `'bathroom_type' toʻldirilishi shart`. Ikkala sxemani QO'LDA solishtirishga
/// to'g'ri keldi, chunki avtomatik qo'riqchi yo'q edi. Sxemalar mos chiqdi
/// (muammo boshqa joyda edi), lekin ular kelajakda ajralib ketsa xato AYNAN
/// shunday ko'rinadi: foydalanuvchi yetti qadam to'ldiradi va oxirida
/// tushunarsiz 400 oladi.
///
/// Ikki tomonlama qo'riqchi:
///   * BU test — Dart sxemasi fixture bilan mos turishini ta'minlaydi;
///   * `kadastr-backend/tests/test_bozor_listing_media.py` — fixture Python
///     sxemasi bilan mos turishini ta'minlaydi.
///
/// Ya'ni ikki sxemadan BIRI o'zgarsa, testlardan biri albatta yiqiladi.
///
/// Sxemani ATAYLAB o'zgartirganda fixture'ni yangilash kerak:
///
///     UPDATE_SCHEMA_FIXTURE=1 flutter test \
///       test/features/bozor/param_schema_parity_test.dart
///
/// So'ng backend testini yurgizib, Python sxemasi ham mos kelganini tekshir
/// (`pytest tests/test_bozor_listing_media.py`) — fixture'ni yangilash
/// nomuvofiqlikni YASHIRMAYDI, faqat uni backend tarafiga surib qo'yadi.

const _fixturePath =
    '../kadastr-backend/tests/fixtures/mobile_param_schema.json';

String _code(PropertyType t) => switch (t) {
  PropertyType.apartment => 'apartment',
  PropertyType.house => 'house',
  PropertyType.land => 'land',
  PropertyType.commercial => 'commercial',
  PropertyType.garage => 'garage',
  PropertyType.otherNonResidential => 'other_non_residential',
};

/// Fixture bilan bir xil shakl. Kalitlar alifbo tartibida — `jsonEncode`
/// tartibi barqaror bo'lsin.
Map<String, Object?> _fieldJson(ParamField f) => {
  'cond': f.visibleWhen != null,
  'control': f.control.name,
  'key': f.key,
  'optional': f.optional,
  'optionsKey': f.optionsKey,
  'unit': f.unit,
};

void main() {
  final file = File(_fixturePath);

  test('param sxemasi backend fixture bilan MOS', () {
    if (!file.existsSync()) {
      // Backend repo yonida bo'lmasa (CI konteyneri) test o'tkazib yuboriladi —
      // Python tarafdagi yarmi baribir fixture'ni tekshiradi.
      markTestSkipped('kadastr-backend yonida yo\'q: $_fixturePath');
      return;
    }

    final actual = <String, List<Map<String, Object?>>>{
      for (final t in PropertyType.values)
        _code(t): [for (final f in t.paramFields) _fieldJson(f)],
    };

    // Golden-file naqshi: fixture'ni QO'LDA tahrirlash o'rniga shu test
    // yozib beradi. Yangilash ATAYLAB bayroq talab qiladi, aks holda
    // qo'riqchi o'zini jimgina yangilab, hech narsani ushlamay qo'yardi.
    if (Platform.environment['UPDATE_SCHEMA_FIXTURE'] == '1') {
      const enc = JsonEncoder.withIndent('  ');
      final sorted = {
        for (final k in actual.keys.toList()..sort()) k: actual[k],
      };
      file.writeAsStringSync('${enc.convert(sorted)}\n');
      markTestSkipped('fixture yangilandi: $_fixturePath');
      return;
    }

    final expected = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    // Turlar to'plami.
    expect(
      actual.keys.toSet(),
      expected.keys.toSet(),
      reason: 'mulk turlari to‘plami fixture bilan farq qiladi',
    );

    for (final type in actual.keys) {
      final exp = (expected[type] as List).cast<Map<String, dynamic>>();
      final act = actual[type]!;

      expect(
        act.map((f) => f['key']).toList(),
        exp.map((f) => f['key']).toList(),
        reason:
            '$type: maydonlar ro‘yxati (yoki TARTIBI) farq qiladi.\n'
            'Sxemani ataylab o‘zgartirgan bo‘lsang fixture‘ni yangila:\n'
            '  UPDATE_SCHEMA_FIXTURE=1 flutter test '
            'test/features/bozor/param_schema_parity_test.dart\n'
            'so‘ng backend sxemasini ham moslab, pytest bilan tekshir.',
      );

      final expByKey = {for (final f in exp) f['key'] as String: f};
      for (final f in act) {
        final e = expByKey[f['key']]!;
        for (final prop in ['optional', 'control', 'cond', 'optionsKey', 'unit']) {
          expect(
            f[prop],
            e[prop],
            reason: '$type.${f['key']}: `$prop` fixture bilan farq qiladi',
          );
        }
      }
    }
  });

  test('fixture‘dagi maydonlar soni kutilgandek', () {
    if (!file.existsSync()) {
      markTestSkipped('backend yonida yo\'q');
      return;
    }
    final expected = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final total = expected.values
        .map((v) => (v as List).length)
        .fold<int>(0, (a, b) => a + b);
    // Bu son o'zgarishi normal — lekin O'YLAMASDAN o'zgarmasligi kerak.
    expect(total, 86, reason: 'sxemaga maydon qo‘shildi/olindi — fixture va '
        'backend sxemasi ikkalasi ham yangilanganini tekshir');
  });
}
