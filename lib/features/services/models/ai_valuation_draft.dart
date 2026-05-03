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
    this.latitude,
    this.longitude,
    this.usageType,
    this.monthlyIncomeUzs,
  });

  final bool scanCompleted;
  final ScanObjectType? objectType;
  final String? viloyat;
  final String? tuman;
  final double? areaM2;
  // Xaritadan tanlangan koordinatalar.
  final double? latitude;
  final double? longitude;
  final AiUsageType? usageType;
  final int? monthlyIncomeUzs;

  bool get hasLocation => latitude != null && longitude != null;

  AiValuationDraft copyWith({
    bool? scanCompleted,
    ScanObjectType? objectType,
    String? viloyat,
    String? tuman,
    double? areaM2,
    double? latitude,
    double? longitude,
    AiUsageType? usageType,
    int? monthlyIncomeUzs,
  }) => AiValuationDraft(
    scanCompleted: scanCompleted ?? this.scanCompleted,
    objectType: objectType ?? this.objectType,
    viloyat: viloyat ?? this.viloyat,
    tuman: tuman ?? this.tuman,
    areaM2: areaM2 ?? this.areaM2,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    usageType: usageType ?? this.usageType,
    monthlyIncomeUzs: monthlyIncomeUzs ?? this.monthlyIncomeUzs,
  );
}
