import 'architecture_order_draft.dart';
import 'package:flutter/widgets.dart';

import '../../../core/i18n/app_translations.dart';

enum ScanObjectType {
  turarJoy('Turar joy', 'residential'),
  noturarJoy('Noturar joy', 'non_residential'),
  ombor('Ombor', 'warehouse'),
  sanoat('Sanoat obyektlari', 'industrial');

  const ScanObjectType(this.label, this.wire);
  final String label;

  /// Backend `ObjectType` enum value (matches app/models/scan.py).
  final String wire;

  String localizedLabel(Locale locale) => switch (this) {
    ScanObjectType.turarJoy => tr(
      locale,
      'scan.object_type.residential',
      uz: 'Turar joy',
      ru: 'Жилое',
      en: 'Residential',
    ),
    ScanObjectType.noturarJoy => tr(
      locale,
      'scan.object_type.non_residential',
      uz: 'Noturar joy',
      ru: 'Нежилое',
      en: 'Non-residential',
    ),
    ScanObjectType.ombor => tr(
      locale,
      'scan.object_type.warehouse',
      uz: 'Ombor',
      ru: 'Склад',
      en: 'Warehouse',
    ),
    ScanObjectType.sanoat => tr(
      locale,
      'scan.object_type.industrial',
      uz: 'Sanoat obyektlari',
      ru: 'Промышленные объекты',
      en: 'Industrial',
    ),
  };
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
