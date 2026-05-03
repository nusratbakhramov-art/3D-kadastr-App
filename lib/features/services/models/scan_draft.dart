import 'architecture_order_draft.dart';

enum ScanObjectType {
  turarJoy('Turar joy'),
  noturarJoy('Noturar joy'),
  ombor('Ombor'),
  sanoat('Sanoat obyektlari');

  const ScanObjectType(this.label);
  final String label;
}

class ScanDraft {
  const ScanDraft({
    required this.cadastreNumber,
    this.objectType,
    this.scanCompleted = false,
    this.viloyat,
    this.tuman,
    this.latitude,
    this.longitude,
    this.tzDraft,
  });

  final String cadastreNumber;
  final ScanObjectType? objectType;
  final bool scanCompleted;
  final String? viloyat;
  final String? tuman;
  // Xaritadan tanlangan koordinatalar (kadastr raqami kiritilgandan keyingi step).
  final double? latitude;
  final double? longitude;
  // Arxitektura TZ wizard'dan to'plangan ma'lumotlar (3D kadastr flow uchun).
  final ArchitectureOrderDraft? tzDraft;

  bool get hasLocation => latitude != null && longitude != null;

  ScanDraft copyWith({
    String? cadastreNumber,
    ScanObjectType? objectType,
    bool? scanCompleted,
    String? viloyat,
    String? tuman,
    double? latitude,
    double? longitude,
    ArchitectureOrderDraft? tzDraft,
  }) => ScanDraft(
    cadastreNumber: cadastreNumber ?? this.cadastreNumber,
    objectType: objectType ?? this.objectType,
    scanCompleted: scanCompleted ?? this.scanCompleted,
    viloyat: viloyat ?? this.viloyat,
    tuman: tuman ?? this.tuman,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    tzDraft: tzDraft ?? this.tzDraft,
  );
}
