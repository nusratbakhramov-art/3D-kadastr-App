import 'scan_draft.dart';

enum AiUsageType {
  rental('Ijaraga beraman'),
  personal('Shaxsiy foydalanish');

  const AiUsageType(this.label);
  final String label;
}

class AiValuationDraft {
  const AiValuationDraft({
    this.scanCompleted = false,
    this.objectType,
    this.viloyat,
    this.tuman,
    this.areaM2,
    this.usageType,
    this.monthlyIncomeUzs,
  });

  final bool scanCompleted;
  final ScanObjectType? objectType;
  final String? viloyat;
  final String? tuman;
  final double? areaM2;
  final AiUsageType? usageType;
  final int? monthlyIncomeUzs;

  AiValuationDraft copyWith({
    bool? scanCompleted,
    ScanObjectType? objectType,
    String? viloyat,
    String? tuman,
    double? areaM2,
    AiUsageType? usageType,
    int? monthlyIncomeUzs,
  }) => AiValuationDraft(
    scanCompleted: scanCompleted ?? this.scanCompleted,
    objectType: objectType ?? this.objectType,
    viloyat: viloyat ?? this.viloyat,
    tuman: tuman ?? this.tuman,
    areaM2: areaM2 ?? this.areaM2,
    usageType: usageType ?? this.usageType,
    monthlyIncomeUzs: monthlyIncomeUzs ?? this.monthlyIncomeUzs,
  );
}
