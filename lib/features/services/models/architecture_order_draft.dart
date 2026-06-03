/// Arxitektura va qurilish loyihasi TZ buyurtma — wizard state modeli.
///
/// 7 stepli wizard davomida foydalanuvchi to'ldiradi va tugagandan keyin
/// `toRequestJson()` orqali backend'ga yuboriladi.
library;

import 'package:flutter/foundation.dart';

import 'ai_baholash_bundle.dart' show AiLocationInfo, AiRoom;

// ────────────────────────────────────────────────────────────────────────
// Enums (backend ArchitectureObjectType bilan mos)
// ────────────────────────────────────────────────────────────────────────

enum ArchObjectType {
  yakkaSmall('yakka_small'),
  yakkaLarge('yakka_large'),
  kopQavatli('kop_qavatli'),
  ofis('ofis'),
  savdoMarkazi('savdo_markazi'),
  mehmonxona('mehmonxona'),
  sanoat('sanoat'),
  omborxona('omborxona'),
  boshqa('boshqa');

  const ArchObjectType(this.apiValue);
  final String apiValue;
}

enum ConstructionType {
  yangi('yangi'),
  rekonstruksiya('rekonstruksiya');

  const ConstructionType(this.apiValue);
  final String apiValue;
}

// ────────────────────────────────────────────────────────────────────────
// Sub-models (details JSONB ichidagi bo'limlar)
// ────────────────────────────────────────────────────────────────────────

class ArchitectureDesignDraft {
  ArchitectureDesignDraft();
  String? style; // high_tech / klassik / neoklassik / minimalizm / loft
  String? facadeMaterial; // gisht / tosh / kompozit / shisha / boyoq
  String? colors;
  bool has3dVisualization = false;

  Map<String, dynamic> toJson() => {
        if (style != null) 'style': style,
        if (facadeMaterial != null) 'facade_material': facadeMaterial,
        if (colors != null) 'colors': colors,
        'has_3d_visualization': has3dVisualization,
      };
}

class ConstructiveDraft {
  ConstructiveDraft();
  String? scheme;
  String? foundation;
  String? walls;
  String? ceiling;
  String? roofType;
  String? roofMaterial;

  Map<String, dynamic> toJson() => {
        if (scheme != null) 'scheme': scheme,
        if (foundation != null) 'foundation': foundation,
        if (walls != null) 'walls': walls,
        if (ceiling != null) 'ceiling': ceiling,
        if (roofType != null) 'roof_type': roofType,
        if (roofMaterial != null) 'roof_material': roofMaterial,
      };
}

class EngineeringDraft {
  EngineeringDraft();
  bool hasGenerator = false;
  String? waterSource; // markaziy / quduq
  String? sewage; // markaziy / septik
  String? heating; // gaz / elektr / qozonxona
  String? ventilation; // tabiiy / mexanik
  String? airConditioning; // split / vrf / chiller
  bool hasFireSystem = false;
  bool hasAlarm = false;
  bool hasVideoSurveillance = false;
  bool hasSolarPanels = false;

  Map<String, dynamic> toJson() => {
        'has_generator': hasGenerator,
        if (waterSource != null) 'water_source': waterSource,
        if (sewage != null) 'sewage': sewage,
        if (heating != null) 'heating': heating,
        if (ventilation != null) 'ventilation': ventilation,
        if (airConditioning != null) 'air_conditioning': airConditioning,
        'has_fire_system': hasFireSystem,
        'has_alarm': hasAlarm,
        'has_video_surveillance': hasVideoSurveillance,
        'has_solar_panels': hasSolarPanels,
      };
}

class TerritoryDraft {
  TerritoryDraft();
  bool hasParking = false;
  int? parkingCount;
  bool hasPaths = false;
  bool hasLandscape = false;
  bool hasPool = false;
  bool hasLighting = false;

  Map<String, dynamic> toJson() => {
        'has_parking': hasParking,
        if (parkingCount != null) 'parking_count': parkingCount,
        'has_paths': hasPaths,
        'has_landscape': hasLandscape,
        'has_pool': hasPool,
        'has_lighting': hasLighting,
      };
}

class TimelineDraft {
  TimelineDraft();
  int? sketchDays;
  int? workingDays;

  Map<String, dynamic> toJson() => {
        if (sketchDays != null) 'sketch_days': sketchDays,
        if (workingDays != null) 'working_days': workingDays,
      };
}

// ────────────────────────────────────────────────────────────────────────
// Asosiy draft (mutable)
// ────────────────────────────────────────────────────────────────────────

class ArchitectureOrderDraft extends ChangeNotifier {
  ArchitectureOrderDraft();

  // Step 1 — Buyurtmachi
  String customerName = '';
  String tin = '';
  String phone = '';
  String email = '';

  // Step 2 — Obyekt
  String objectName = '';
  String address = '';
  String cadastreNumber = '';
  double? landAreaSqm;
  String landUsePurpose = '';
  // Xaritadan tanlangan manzil (koordinatalar bilan). `address` matni shundan
  // to'ldiriladi; koordinatalar `details.location` ichida saqlanadi.
  AiLocationInfo? location;

  // Step 3 — Loyiha umumiy
  ArchObjectType? objectType;
  String objectSubtype = '';
  ConstructionType constructionType = ConstructionType.yangi;
  int? floors;
  bool hasBasement = false;
  bool hasMansard = false;
  bool hasUndergroundParking = false;
  double? totalAreaSqm;
  double? buildingAreaSqm;
  double? maxHeightM;
  // Qurilish yili — AI baholashda eskirish koeffitsienti uchun muhim faktor.
  int? constructionYear;

  // Step 3 — Xonalar tarkibi (AI baholash bilan bir xil model)
  final List<AiRoom> rooms = [];

  // Steps 4-7 — sub-models
  final ArchitectureDesignDraft architecture = ArchitectureDesignDraft();
  final ConstructiveDraft constructive = ConstructiveDraft();
  final EngineeringDraft engineering = EngineeringDraft();
  final TerritoryDraft territory = TerritoryDraft();
  final TimelineDraft timeline = TimelineDraft();
  String notes = '';

  // ── Validatsiya yordamchilari ────────────────────────────────────────
  bool get isStep1Valid =>
      customerName.trim().length >= 2 && phone.trim().length >= 5;
  bool get isStep2Valid => true; // hammasi optional
  bool get isStep3Valid => objectType != null;
  bool get isStep4Valid => true;
  bool get isStep5Valid => true;
  bool get isStep6Valid => true;
  bool get isStep7Valid => true;

  bool get canSubmit => isStep1Valid && isStep3Valid;

  // ── State o'zgarganini bildirish ─────────────────────────────────────
  void touch() => notifyListeners();

  // ── Backend API uchun JSON ───────────────────────────────────────────
  Map<String, dynamic> toRequestJson() {
    return {
      'customer_name': customerName.trim(),
      if (tin.trim().isNotEmpty) 'tin': tin.trim(),
      'phone': phone.trim(),
      if (email.trim().isNotEmpty) 'email': email.trim(),
      if (objectName.trim().isNotEmpty) 'object_name': objectName.trim(),
      if (address.trim().isNotEmpty) 'address': address.trim(),
      if (cadastreNumber.trim().isNotEmpty)
        'cadastre_number': cadastreNumber.trim(),
      if (landAreaSqm != null) 'land_area_sqm': landAreaSqm,
      if (landUsePurpose.trim().isNotEmpty)
        'land_use_purpose': landUsePurpose.trim(),
      if (constructionYear != null) 'construction_year': constructionYear,
      'object_type': objectType!.apiValue,
      if (objectSubtype.trim().isNotEmpty)
        'object_subtype': objectSubtype.trim(),
      'construction_type': constructionType.apiValue,
      if (floors != null) 'floors': floors,
      'has_basement': hasBasement,
      'has_mansard': hasMansard,
      'has_underground_parking': hasUndergroundParking,
      if (totalAreaSqm != null) 'total_area_sqm': totalAreaSqm,
      if (buildingAreaSqm != null) 'building_area_sqm': buildingAreaSqm,
      if (maxHeightM != null) 'max_height_m': maxHeightM,
      'details': {
        if (location != null) 'location': location!.toJson(),
        // Backend RoomEntry sxemasi {name, count, area_sqm} kutadi — AiRoom'ni
        // shu shaklga moslaymiz (standart turlar uchun nom = labelUz).
        'rooms': rooms.map((r) {
          final name = (r.name?.trim().isNotEmpty ?? false)
              ? r.name!.trim()
              : r.kind.labelUz;
          return {
            'name': name,
            'count': r.count,
            if (r.area != null) 'area_sqm': r.area,
          };
        }).toList(),
        'architecture': architecture.toJson(),
        'constructive': constructive.toJson(),
        'engineering': engineering.toJson(),
        'territory': territory.toJson(),
        'timeline': timeline.toJson(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    };
  }
}
