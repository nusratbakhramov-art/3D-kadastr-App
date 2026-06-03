/// Dizayn loyihasi TZ buyurtma — wizard state modeli.
///
/// 7 stepli dizayn wizard davomida foydalanuvchi to'ldiradi va tugagandan
/// keyin `toRequestJson()` orqali backend'ga (`/services/design/orders`)
/// yuboriladi. Backend `DesignOrderCreate` sxemasi bilan mos.
library;

import 'package:flutter/foundation.dart';

import 'ai_baholash_bundle.dart' show AiLocationInfo;

// ────────────────────────────────────────────────────────────────────────
// Enums (backend DesignObjectType / DesignType bilan mos)
// ────────────────────────────────────────────────────────────────────────

enum DizObjectType {
  yakka('yakka'),
  kopQavatliKvartira('kop_qavatli_kvartira'),
  savdoMarkazi('savdo_markazi'),
  ofis('ofis'),
  mehmonxona('mehmonxona'),
  sanoat('sanoat'),
  omborxona('omborxona'),
  boshqa('boshqa');

  const DizObjectType(this.apiValue);
  final String apiValue;
}

enum DizDesignType {
  yangi('yangi'),
  rekonstruksiya('rekonstruksiya');

  const DizDesignType(this.apiValue);
  final String apiValue;
}

// ────────────────────────────────────────────────────────────────────────
// Sub-models (details JSONB ichidagi bo'limlar)
// ────────────────────────────────────────────────────────────────────────

class DizaynInteriorDraft {
  DizaynInteriorDraft();
  String? style; // high_tech / klassik / neoklassik / minimalizm / loft / boshqa
  String? interiorMaterial; // boyoq / tosh / kompozit / shisha / bambuk
  String? colors;
  String? floorMaterial; // laminat / tosh / kafel / boshqa
  bool has3dVisualization = false;
  bool hasWorkingDrawings = false;
  bool hasAuthorSupervision = false;

  Map<String, dynamic> toJson() => {
        if (style != null) 'style': style,
        if (interiorMaterial != null) 'interior_material': interiorMaterial,
        if (colors != null) 'colors': colors,
        if (floorMaterial != null) 'floor_material': floorMaterial,
        'has_3d_visualization': has3dVisualization,
        'has_working_drawings': hasWorkingDrawings,
        'has_author_supervision': hasAuthorSupervision,
      };
}

class DizaynEngineeringDraft {
  DizaynEngineeringDraft();
  bool hasElectricalDrawings = false;
  bool hasPlumbingDrawings = false;
  bool hasDemolitionPlan = false;
  bool hasMontagePlan = false;
  bool hasGypsumPlan = false;
  String? partitionMaterial; // gisht / gipsokarton / gazoblok
  String? airConditioning; // split / vrf / chiller
  bool hasFireSystem = false;
  bool hasVideoSurveillance = false;
  bool hasFurnitureLayout = false;

  Map<String, dynamic> toJson() => {
        'has_electrical_drawings': hasElectricalDrawings,
        'has_plumbing_drawings': hasPlumbingDrawings,
        'has_demolition_plan': hasDemolitionPlan,
        'has_montage_plan': hasMontagePlan,
        'has_gypsum_plan': hasGypsumPlan,
        if (partitionMaterial != null) 'partition_material': partitionMaterial,
        if (airConditioning != null) 'air_conditioning': airConditioning,
        'has_fire_system': hasFireSystem,
        'has_video_surveillance': hasVideoSurveillance,
        'has_furniture_layout': hasFurnitureLayout,
      };
}

class DizaynExteriorDraft {
  DizaynExteriorDraft();
  String? style; // high_tech / klassik / neoklassik / minimalizm / loft / modern
  String? exteriorMaterial; // boyoq / tosh / kompozit / shisha
  String? colors;
  bool hasParking = false;
  int? parkingCount;
  bool hasPaths = false;
  bool hasLandscape = false;
  bool hasPool = false;
  bool hasLighting = false;

  Map<String, dynamic> toJson() => {
        if (style != null) 'style': style,
        if (exteriorMaterial != null) 'exterior_material': exteriorMaterial,
        if (colors != null) 'colors': colors,
        'has_parking': hasParking,
        if (parkingCount != null) 'parking_count': parkingCount,
        'has_paths': hasPaths,
        'has_landscape': hasLandscape,
        'has_pool': hasPool,
        'has_lighting': hasLighting,
      };
}

class DizaynTimelineDraft {
  DizaynTimelineDraft();
  int? designDays;
  int? workingDrawingsDays;

  Map<String, dynamic> toJson() => {
        if (designDays != null) 'design_days': designDays,
        if (workingDrawingsDays != null)
          'working_drawings_days': workingDrawingsDays,
      };
}

// ────────────────────────────────────────────────────────────────────────
// Asosiy draft (mutable)
// ────────────────────────────────────────────────────────────────────────

class DizaynOrderDraft extends ChangeNotifier {
  DizaynOrderDraft();

  // Step 1 — Buyurtmachi
  String customerName = '';
  String tin = '';
  String phone = '';
  String email = '';

  // Step 2 — Obyekt va o'lchamlar
  String objectName = '';
  String address = '';
  // Xaritadan tanlangan manzil (koordinatalar bilan).
  AiLocationInfo? location;
  DizObjectType? objectType;
  String objectSubtype = '';
  DizDesignType designType = DizDesignType.yangi;
  int? floors;
  int? roomsCount;
  bool hasBasement = false;
  bool hasMansard = false;
  double? totalAreaSqm;
  double? interiorAreaSqm;
  double? designAreaSqm;
  double? ceilingHeightM;

  // Step 3 — Qo'shimcha xonalar (erkin matn)
  String extraRooms = '';

  // Steps 4-7 — sub-models
  final DizaynInteriorDraft interior = DizaynInteriorDraft();
  final DizaynEngineeringDraft engineering = DizaynEngineeringDraft();
  final DizaynExteriorDraft exterior = DizaynExteriorDraft();
  final DizaynTimelineDraft timeline = DizaynTimelineDraft();
  String notes = '';

  // ── Validatsiya yordamchilari ────────────────────────────────────────
  bool get isStep1Valid =>
      customerName.trim().length >= 2 && phone.trim().length >= 5;
  bool get isStep2Valid => objectType != null;

  bool get canSubmit => isStep1Valid && isStep2Valid;

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
      'object_type': objectType!.apiValue,
      if (objectSubtype.trim().isNotEmpty)
        'object_subtype': objectSubtype.trim(),
      'design_type': designType.apiValue,
      if (floors != null) 'floors': floors,
      if (roomsCount != null) 'rooms_count': roomsCount,
      'has_basement': hasBasement,
      'has_mansard': hasMansard,
      if (totalAreaSqm != null) 'total_area_sqm': totalAreaSqm,
      if (interiorAreaSqm != null) 'interior_area_sqm': interiorAreaSqm,
      if (designAreaSqm != null) 'design_area_sqm': designAreaSqm,
      if (ceilingHeightM != null) 'ceiling_height_m': ceilingHeightM,
      'details': {
        if (location != null) 'location': location!.toJson(),
        if (extraRooms.trim().isNotEmpty) 'extra_rooms': extraRooms.trim(),
        'interior': interior.toJson(),
        'engineering': engineering.toJson(),
        'exterior': exterior.toJson(),
        'timeline': timeline.toJson(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    };
  }
}
