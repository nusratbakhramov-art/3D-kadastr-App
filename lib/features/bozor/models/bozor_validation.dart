/// Qoralamaning YAKUNIY tekshiruvi — yuborishdan oldingi oxirgi darvoza.
///
/// NEGA KERAK. Har bir sehrgar qadami o'zining `_isComplete` iga ega va
/// "Далее" ni bloklaydi — bu qadamlarni KETMA-KET bosib o'tganda ishlaydi.
/// Lekin qoralamani davom ettirish (`openBozorDraft`) sehrgarni SAQLANGAN
/// qadamdan ochadi: `current_step == 'terms'` bo'lsa foydalanuvchi to'g'ridan
/// 7-qadamga tushadi va 1–6 qadamlarning validatsiyasi UMUMAN chetlab
/// o'tiladi. 7-qadam esa faqat rozilik belgisini tekshirardi.
///
/// Natijasi prod'da ko'rindi (2026-09-10): foydalanuvchi qoralamani davom
/// ettirib "Joylashtirish" ni bosdi va serverdan tushunarsiz 400 oldi —
/// `'bathroom_type' toʻldirilishi shart`. Maydon 3-qadamda edi, u esa
/// ochilmagan ham.
///
/// Shu sababli bu yerda BITTA joyda hamma qadamning qoidasi takrorlanadi va
/// 7-qadam yuborishdan oldin shuni so'raydi. Qoidalar ekranlardagi
/// `_isComplete` lar bilan mos bo'lishi kerak — o'zgartirilsa ikkalasi ham.
library;

import 'bozor_draft.dart';
import 'param_schema.dart';

/// Yetishmayotgan narsa: qaysi qadamda va (agar aniq bo'lsa) qaysi maydon.
class DraftBlocker {
  const DraftBlocker({
    required this.step,
    required this.stepTitleKey,
    this.fieldLabelKeys = const [],
  });

  final WizardStep step;

  /// Qadam sarlavhasining i18n kaliti — foydalanuvchiga QAYERGA qaytishni
  /// aytish uchun.
  final String stepTitleKey;

  /// Aniq maydonlar (`bozor.param.*`). Bo'sh bo'lishi mumkin: ba'zi
  /// qadamlarda maydon darajasidagi kalit yo'q, qadam nomi yetadi.
  final List<String> fieldLabelKeys;
}

/// Qadam → sarlavha kaliti. Ekranlardagi `ServiceAppBar` bilan bir xil.
const Map<WizardStep, String> kStepTitleKeys = {
  WizardStep.type: 'bozor.step.type.title',
  WizardStep.address: 'bozor.address.title',
  WizardStep.params: 'bozor.params.title',
  WizardStep.price: 'bozor.price.title',
  WizardStep.description: 'bozor.desc.title',
  WizardStep.contacts: 'bozor.contacts.title',
  WizardStep.terms: 'bozor.terms.title',
};

/// To'ldirilmagan MAJBURIY parametrlar (3-qadam + "Barcha parametrlar").
///
/// Shartli maydon sharti bajarilmasa TALAB QILINMAYDI, toggle esa hech qachon
/// bo'sh bo'lmaydi (`null` = o'chirilgan).
List<ParamField> missingRequiredParams(BozorDraft draft) {
  final type = draft.type;
  if (type == null) return const [];
  return [
    for (final f in visibleParams(type.paramFields, draft.params))
      if (!f.optional &&
          f.control != ParamControl.toggle &&
          _isEmpty(draft.params[f.key]))
        f,
  ];
}

/// Qoralamani yuborishga to'sqinlik qiladigan hamma narsa, QADAM tartibida.
///
/// Bo'sh ro'yxat = yuborish mumkin. Rozilik belgisi bu yerda TEKSHIRILMAYDI —
/// u 7-qadam ekranining o'z ishi (tugma shunga qarab yonadi).
List<DraftBlocker> draftBlockers(BozorDraft draft) {
  final out = <DraftBlocker>[];

  void add(WizardStep step, [List<String> fields = const []]) =>
      out.add(DraftBlocker(
        step: step,
        stepTitleKey: kStepTitleKeys[step]!,
        fieldLabelKeys: fields,
      ));

  // 1-qadam.
  final type = draft.type;
  if (draft.deal == null || draft.kind == null || type == null) {
    add(WizardStep.type);
    // Turi yo'q bo'lsa qolgan qadamlarning qoidalari ham noaniq — shu yerda
    // to'xtaymiz, aks holda "hamma narsa yetishmaydi" degan foydasiz ro'yxat
    // chiqadi.
    return out;
  }

  // 2-qadam. `AddressDraft` dagi majburiy qatorlar — ekran bilan bir xil.
  final a = draft.address;
  final addressFields = <String>[
    if (a.regionId == null) 'bozor.address.field.region',
    if (a.districtId == null) 'bozor.address.field.district',
    if (a.address.trim().isEmpty) 'bozor.address.field.address',
    for (final row in type.addressRows)
      if (_requiredAddressRow(row, a)) _addressRowKey(row),
  ];
  if (addressFields.isNotEmpty) add(WizardStep.address, addressFields);

  // 3-qadam (variantda bo'lmasa o'tkazib yuboriladi).
  if (draft.wizardSteps.contains(WizardStep.params)) {
    final missing = missingRequiredParams(draft);
    if (missing.isNotEmpty) {
      add(WizardStep.params, [for (final f in missing) f.labelKey]);
    }
  }

  // 4-qadam.
  if (draft.price.amount.trim().isEmpty) add(WizardStep.price);

  // 5-qadam.
  if (draft.title.trim().length < 3 || draft.description.text.trim().isEmpty) {
    add(WizardStep.description);
  }

  // 6-qadam. Telefon — 9 raqam (`+998` siz), ekrandagi qoida bilan bir xil.
  final c = draft.contacts;
  final firstPhone = c.phones.isEmpty ? '' : c.phones.first;
  if (c.name.trim().isEmpty || _digits(firstPhone).length != 9) {
    add(WizardStep.contacts);
  }

  return out;
}

bool _isEmpty(Object? v) {
  if (v == null) return true;
  if (v is String) return v.trim().isEmpty;
  if (v is List) return v.isEmpty;
  return false;
}

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Shu qator majburiy va BO'SHMI. Mo'ljal va podyezd ixtiyoriy — ekrandagi
/// `_isComplete` bilan bir xil qoida.
bool _requiredAddressRow(AddressRow row, AddressDraft a) => switch (row) {
  AddressRow.apartmentNumber => a.apartmentNumber.trim().isEmpty,
  AddressRow.houseNumber => a.houseNumber.trim().isEmpty,
  AddressRow.totalFloors => a.totalFloors.trim().isEmpty,
  AddressRow.floor => a.floor.trim().isEmpty,
  _ => false,
};

String _addressRowKey(AddressRow row) => switch (row) {
  AddressRow.apartmentNumber => 'bozor.address.field.apartment_number',
  AddressRow.houseNumber => 'bozor.address.field.house_number',
  AddressRow.totalFloors => 'bozor.address.field.total_floors',
  AddressRow.floor => 'bozor.address.field.floor',
  AddressRow.region => 'bozor.address.field.region',
  AddressRow.district => 'bozor.address.field.district',
  AddressRow.address => 'bozor.address.field.address',
  AddressRow.landmark => 'bozor.address.field.landmark',
  AddressRow.entrance => 'bozor.address.field.entrance',
};
