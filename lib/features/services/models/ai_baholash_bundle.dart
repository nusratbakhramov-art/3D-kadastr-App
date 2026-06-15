/// In-memory bundle shared across the new AI Baholash wizard steps
/// (kadastr → client form → location → submit).
///
/// Each step pushes a partial copy via the next route's constructor; the
/// submit screen serializes the full thing for `POST /api/v1/ai-valuations`.
library;

import 'dart:ui' show Locale;

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
          if (kadastr.totalArea != null) 'total_area': kadastr.totalArea,
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

  String get labelUz => switch (this) {
    ValuationPurpose.sale => 'Sotish',
    ValuationPurpose.mortgage => 'Ipoteka / kredit',
    ValuationPurpose.insurance => "Sug'urta",
    ValuationPurpose.court => 'Sud / nizo',
    ValuationPurpose.tax => 'Soliq',
  };

  String get hintUz => switch (this) {
    ValuationPurpose.sale => 'Bozor narxi asosida',
    ValuationPurpose.mortgage => 'Bank garovi uchun',
    ValuationPurpose.insurance => 'Qayta tiklash qiymati',
    ValuationPurpose.court => '3 yondashuv teng',
    ValuationPurpose.tax => 'Kadastr asosida',
  };

  String label(Locale l) => switch (l.languageCode) {
    'ru' => switch (this) {
      ValuationPurpose.sale => 'Продажа',
      ValuationPurpose.mortgage => 'Ипотека / кредит',
      ValuationPurpose.insurance => 'Страхование',
      ValuationPurpose.court => 'Суд / спор',
      ValuationPurpose.tax => 'Налог',
    },
    'en' => switch (this) {
      ValuationPurpose.sale => 'Sale',
      ValuationPurpose.mortgage => 'Mortgage / loan',
      ValuationPurpose.insurance => 'Insurance',
      ValuationPurpose.court => 'Court / dispute',
      ValuationPurpose.tax => 'Tax',
    },
    _ => labelUz,
  };

  String hint(Locale l) => switch (l.languageCode) {
    'ru' => switch (this) {
      ValuationPurpose.sale => 'По рыночной цене',
      ValuationPurpose.mortgage => 'Для банковского залога',
      ValuationPurpose.insurance => 'Восстановительная стоимость',
      ValuationPurpose.court => '3 подхода равны',
      ValuationPurpose.tax => 'На основе кадастра',
    },
    'en' => switch (this) {
      ValuationPurpose.sale => 'Based on market price',
      ValuationPurpose.mortgage => 'For bank collateral',
      ValuationPurpose.insurance => 'Replacement value',
      ValuationPurpose.court => '3 approaches equal',
      ValuationPurpose.tax => 'Cadastre-based',
    },
    _ => hintUz,
  };
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

  String label(Locale l) => switch (l.languageCode) {
    'ru' => switch (this) {
      RoomKind.living => 'Гостиная',
      RoomKind.bedroom => 'Спальня',
      RoomKind.kitchen => 'Кухня',
      RoomKind.bathroom => 'Ванная',
      RoomKind.hallway => 'Коридор',
      RoomKind.balcony => 'Балкон',
      RoomKind.storage => 'Кладовая',
      RoomKind.other => 'Другое',
    },
    'en' => switch (this) {
      RoomKind.living => 'Living room',
      RoomKind.bedroom => 'Bedroom',
      RoomKind.kitchen => 'Kitchen',
      RoomKind.bathroom => 'Bathroom',
      RoomKind.hallway => 'Hallway',
      RoomKind.balcony => 'Balcony',
      RoomKind.storage => 'Storage',
      RoomKind.other => 'Other',
    },
    _ => labelUz,
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
