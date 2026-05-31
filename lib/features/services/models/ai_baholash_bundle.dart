/// In-memory bundle shared across the new AI Baholash wizard steps
/// (kadastr → client form → location → submit).
///
/// Each step pushes a partial copy via the next route's constructor; the
/// submit screen serializes the full thing for `POST /api/v1/ai-valuations`.
library;

import '../api_cadastre_service.dart';

class AiBaholashBundle {
  AiBaholashBundle({
    required this.kadastr,
    this.client,
    this.location,
    this.purpose = ValuationPurpose.sale,
    List<AiRoom>? rooms,
    List<String>? imageKeys,
    List<String>? kadastrKeys,
    List<String>? passportKeys,
  })  : rooms = rooms ?? <AiRoom>[],
        imageKeys = imageKeys ?? <String>[],
        kadastrKeys = kadastrKeys ?? <String>[],
        passportKeys = passportKeys ?? <String>[];

  final CadastreLookupResult kadastr;
  AiClientInfo? client;
  AiLocationInfo? location;

  /// Baholash maqsadi — drives the reconciliation weighting on the backend.
  ValuationPurpose purpose;

  /// Optional dynamic room breakdown.
  final List<AiRoom> rooms;

  /// S3 object keys returned by `POST /ai-valuations/upload`, per category.
  final List<String> imageKeys; // property photos (property_photo)
  final List<String> kadastrKeys; // kadastr docs (kadastr)
  final List<String> passportKeys; // owner ID (passport)

  Map<String, dynamic> toJson() => {
        'kadastr': {
          'cadastre_number': kadastr.cadastreNumber,
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
        if (rooms.isNotEmpty) 'rooms': rooms.map((r) => r.toJson()).toList(),
        if (imageKeys.isNotEmpty) 'image_keys': imageKeys,
        if (kadastrKeys.isNotEmpty) 'kadastr_keys': kadastrKeys,
        if (passportKeys.isNotEmpty) 'passport_keys': passportKeys,
      };
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
}

/// One room in the optional breakdown. Mirrors backend `RoomInput`.
class AiRoom {
  AiRoom({required this.kind, this.name, this.count = 1, this.area});

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
}

class AiClientInfo {
  const AiClientInfo({
    required this.name,
    required this.stir,
    required this.phone,
    required this.email,
  });

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
