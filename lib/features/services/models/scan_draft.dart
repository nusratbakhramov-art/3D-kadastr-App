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
  });

  final String cadastreNumber;
  final ScanObjectType? objectType;
  final bool scanCompleted;
  final String? viloyat;
  final String? tuman;

  ScanDraft copyWith({
    String? cadastreNumber,
    ScanObjectType? objectType,
    bool? scanCompleted,
    String? viloyat,
    String? tuman,
  }) => ScanDraft(
    cadastreNumber: cadastreNumber ?? this.cadastreNumber,
    objectType: objectType ?? this.objectType,
    scanCompleted: scanCompleted ?? this.scanCompleted,
    viloyat: viloyat ?? this.viloyat,
    tuman: tuman ?? this.tuman,
  );
}
