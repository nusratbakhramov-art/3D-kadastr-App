/// In-memory bundle shared across the new AI Baholash wizard steps
/// (kadastr → client form → location → submit).
///
/// Each step pushes a partial copy via the next route's constructor; the
/// submit screen serializes the full thing for `POST /api/v1/ai-valuations`.
library;

import 'dart:ui' show Locale;

import '../../../core/i18n/app_translations.dart';
import '../api_cadastre_service.dart';
import 'ai_scan_result.dart';

class AiBaholashBundle {
  AiBaholashBundle({
    required this.kadastr,
    this.scan,
    this.draftId,
    this.client,
    this.location,
    this.purpose = ValuationPurpose.sale,
    this.purposeBasis,
    this.addressee,
    this.areaM2,
    this.targetSellPrice,
    this.floor,
    this.totalFloors,
    List<AiRoom>? rooms,
    List<String>? imageKeys,
    List<String>? kadastrKeys,
    List<String>? passportKeys,
    List<String>? imagePaths,
    List<String>? kadastrPaths,
    List<String>? passportPaths,
  }) : rooms = rooms ?? <AiRoom>[],
       imageKeys = imageKeys ?? <String>[],
       kadastrKeys = kadastrKeys ?? <String>[],
       passportKeys = passportKeys ?? <String>[],
       imagePaths = imagePaths ?? <String>[],
       kadastrPaths = kadastrPaths ?? <String>[],
       passportPaths = passportPaths ?? <String>[];

  final CadastreLookupResult kadastr;

  /// 3D LiDAR skan natijasi (AI Baholashning birinchi qadami). Mobil-only
  /// fazada faqat lokalda saqlanadi — toJson hozircha yubormaydi.
  final AiScanResult? scan;

  /// Backend DRAFT ariza id (skandan keyin yaratiladi). Har qadamda
  /// `updateDraft` shu id bilan saqlanadi. null = draft yo'q (login/offline).
  int? draftId;

  AiClientInfo? client;
  AiLocationInfo? location;

  /// Baholash maqsadi — drives the reconciliation weighting on the backend.
  ValuationPurpose purpose;

  /// Баҳолаш максади — free-text legal basis printed in the Хисобот
  /// ("…Бош прокуратурасининг … хати асосида … тақдим қилиш учун").
  String? purposeBasis;

  /// Кимга тақдим этилади — cover-letter addressee ("… га").
  String? addressee;

  /// Object area (m²) the user enters up front, right after the scan — its own
  /// step, before the (now optional) davreestr lookup. Feeds `total_area` in the
  /// submit payload (so the valuation + admin use it even when davreestr is
  /// skipped) and is echoed to `area_m2` via the target-price PATCH.
  double? areaM2;

  /// SMETA (construction / replacement) cost (so'm) the user optionally enters
  /// on the «Smeta qiymati» step. When given, the backend uses it to DRIVE the
  /// cost approach (replacement cost → wear + land → reconciliation). Not sent in
  /// the create payload — the status screen PATCHes it right after the job is
  /// created (`/target-price`). Field name kept for wire/DB compatibility.
  double? targetSellPrice;

  /// Which floor the object is on, and total floors in the building. Both are
  /// required by the intake step and adjust the market value (ground/top floor
  /// discount).
  int? floor;
  int? totalFloors;

  /// Optional dynamic room breakdown.
  final List<AiRoom> rooms;

  /// S3 object keys returned by `POST /ai-valuations/upload`, per category.
  final List<String> imageKeys; // property photos (property_photo)
  final List<String> kadastrKeys; // kadastr docs (kadastr)
  final List<String> passportKeys; // owner ID (passport)

  /// Local on-device file paths, index-aligned with the *Keys lists above.
  /// Transient — NOT serialized. Used only to render thumbnails on the review
  /// step and to restore the intake tiles when the user navigates back to edit.
  final List<String> imagePaths;
  final List<String> kadastrPaths;
  final List<String> passportPaths;

  Map<String, dynamic> toJson() => {
        'kadastr': {
          // Skip qilinganda cadastre_number bo'sh bo'lishi mumkin; backend uni
          // MAJBURIY (XX:XX:XX:XX:XX:XXXX format) deb tekshiradi → bo'sh bo'lsa
          // test placeholder yuboramiz (aks holda POST /ai-valuations 422).
          'cadastre_number': kadastr.cadastreNumber.trim().isEmpty
              ? '00:00:00:00:00:0000'
              : kadastr.cadastreNumber,
          if (kadastr.address != null) 'address': kadastr.address,
          if (kadastr.objectTypeHint != null)
            'object_type_hint': kadastr.objectTypeHint,
          if ((areaM2 ?? kadastr.totalArea) != null)
            'total_area': areaM2 ?? kadastr.totalArea,
          if (kadastr.livingArea != null) 'living_area': kadastr.livingArea,
          if (kadastr.cadastreValue != null)
            'cadastre_value': kadastr.cadastreValue,
        },
        if (client != null) 'client': client!.toJson(),
        if (location != null) 'location': location!.toJson(),
        'purpose': purpose.wire,
        if (purposeBasis != null && purposeBasis!.trim().isNotEmpty)
          'purpose_text': purposeBasis!.trim(),
        if (addressee != null && addressee!.trim().isNotEmpty)
          'addressee': addressee!.trim(),
        if (floor != null) 'floor': floor,
        if (totalFloors != null) 'total_floors': totalFloors,
        if (rooms.isNotEmpty) 'rooms': rooms.map((r) => r.toJson()).toList(),
        if (imageKeys.isNotEmpty) 'image_keys': imageKeys,
        if (kadastrKeys.isNotEmpty) 'kadastr_keys': kadastrKeys,
        if (passportKeys.isNotEmpty) 'passport_keys': passportKeys,
      };

  /// Draft `request_payload`'dan bundle qayta tiklash (resume). `draftId` —
  /// davom ettirilayotgan ariza id'si.
  factory AiBaholashBundle.fromJson(Map<String, dynamic> j, {int? draftId}) {
    final k = (j['kadastr'] as Map?)?.cast<String, dynamic>() ?? const {};
    final bundle = AiBaholashBundle(
      kadastr: CadastreLookupResult.fromJson(k),
      draftId: draftId,
      purpose: ValuationPurpose.fromWire(j['purpose'] as String?),
      areaM2: (k['total_area'] as num?)?.toDouble(),
      floor: (j['floor'] as num?)?.toInt(),
      totalFloors: (j['total_floors'] as num?)?.toInt(),
      rooms: ((j['rooms'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => AiRoom.fromJson(e.cast<String, dynamic>()))
          .toList(),
      imageKeys:
          ((j['image_keys'] as List?) ?? const []).map((e) => '$e').toList(),
      kadastrKeys:
          ((j['kadastr_keys'] as List?) ?? const []).map((e) => '$e').toList(),
      passportKeys:
          ((j['passport_keys'] as List?) ?? const []).map((e) => '$e').toList(),
    );
    final c = j['client'];
    if (c is Map) {
      bundle.client = AiClientInfo.fromJson(c.cast<String, dynamic>());
    }
    final loc = j['location'];
    if (loc is Map) {
      bundle.location = AiLocationInfo.fromJson(loc.cast<String, dynamic>());
    }
    bundle.purposeBasis = j['purpose_text'] as String?;
    bundle.addressee = j['addressee'] as String?;
    return bundle;
  }
}

/// Baholash maqsadi — mirrors backend `ValuationPurpose`.
enum ValuationPurpose {
  sale('sale'),
  mortgage('mortgage'),
  insurance('insurance'),
  court('court'),
  tax('tax');

  const ValuationPurpose(this.wire);
  final String wire;

  static ValuationPurpose fromWire(String? w) => ValuationPurpose.values
      .firstWhere((p) => p.wire == w, orElse: () => ValuationPurpose.sale);

  String label(Locale l) => switch (this) {
    ValuationPurpose.sale => tr(l, 'purpose.sale'),
    // Credit-only framing removed; now Bank / Mortgage / Leasing.
    ValuationPurpose.mortgage => tr(l, 'purpose.mortgage'),
    ValuationPurpose.insurance => tr(l, 'purpose.insurance'),
    ValuationPurpose.court => tr(l, 'purpose.court'),
    ValuationPurpose.tax => tr(l, 'purpose.tax'),
  };

  String hint(Locale l) => '';
}

/// One room in the optional breakdown. Mirrors backend `RoomInput`.
class AiRoom {
  AiRoom({required this.kind, this.name, this.count = 1, this.area});

  factory AiRoom.fromJson(Map<String, dynamic> j) => AiRoom(
        kind: RoomKind.values.firstWhere(
          (k) => k.wire == j['kind'],
          orElse: () => RoomKind.other,
        ),
        name: j['name'] as String?,
        count: (j['count'] as num?)?.toInt() ?? 1,
        area: (j['area'] as num?)?.toDouble(),
      );

  RoomKind kind;
  String? name;
  int count;
  double? area;

  Map<String, dynamic> toJson() => {
    'kind': kind.wire,
    if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
    'count': count,
    if (area != null) 'area': area,
  };
}

/// Room types — mirrors backend `RoomKind`.
enum RoomKind {
  living('living', 'Mehmonxona'),
  bedroom('bedroom', 'Yotoqxona'),
  kitchen('kitchen', 'Oshxona'),
  bathroom('bathroom', 'Hammom'),
  hallway('hallway', 'Koridor'),
  balcony('balcony', 'Balkon'),
  storage('storage', 'Ombor'),
  other('other', 'Boshqa');

  const RoomKind(this.wire, this.labelUz);
  final String wire;
  final String labelUz;

  String label(Locale l) => switch (this) {
    RoomKind.living => tr(l, 'services.model.room.living'),
    RoomKind.bedroom => tr(l, 'services.model.room.bedroom'),
    RoomKind.kitchen => tr(l, 'services.model.room.kitchen'),
    RoomKind.bathroom => tr(l, 'services.model.room.bathroom'),
    RoomKind.hallway => tr(l, 'services.model.room.hallway'),
    RoomKind.balcony => tr(l, 'services.model.room.balcony'),
    RoomKind.storage => tr(l, 'services.model.room.storage'),
    RoomKind.other => tr(l, 'services.model.room.other'),
  };
}

class AiClientInfo {
  const AiClientInfo({
    required this.name,
    required this.stir,
    required this.phone,
    required this.email,
  });

  factory AiClientInfo.fromJson(Map<String, dynamic> j) => AiClientInfo(
        name: j['name']?.toString() ?? '',
        stir: j['stir']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
      );

  /// Free text — person name or company name.
  final String name;

  /// Exactly 9 digits (legal-entity STIR) or 14 digits (individual JSHSHIR/
  /// PINFL). No other length passes server-side validation.
  final String stir;

  /// `998XXXXXXXXX` — 12 digits, no leading `+`. Matches the auth pattern.
  final String phone;

  final String email;

  Map<String, dynamic> toJson() => {
    'name': name,
    'stir': stir,
    'phone': phone,
    'email': email,
  };
}

class AiLocationInfo {
  const AiLocationInfo({
    required this.lat,
    required this.lng,
    this.addressText,
  });

  factory AiLocationInfo.fromJson(Map<String, dynamic> j) => AiLocationInfo(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        addressText: j['address_text'] as String?,
      );

  final double lat;
  final double lng;

  /// Reverse-geocoded text the user confirmed. `null` if user picked the
  /// pin without typing/confirming an address.
  final String? addressText;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (addressText != null) 'address_text': addressText,
  };
}
