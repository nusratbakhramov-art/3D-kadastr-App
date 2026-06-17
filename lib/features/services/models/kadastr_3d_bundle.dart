/// In-memory bundle shared across the 3D Kadastr wizard steps
/// (kadastr → client → location → object type → intake → LiDAR scan → submit).
///
/// Mirrors [AiBaholashBundle] but drops `purpose` and the owner/passport
/// documents, and adds the 3D-specific `objectType` and `scanKeys` (LiDAR
/// mesh files). The submit screen serializes the full thing for
/// `POST /api/v1/3d-kadastr-jobs`.
///
/// The client / location / room value types are reused verbatim from the
/// AI Baholash bundle — they validate identically on the backend.
library;

import '../api_cadastre_service.dart';
import '../api_kadastr_3d_job_service.dart' show ObjectTypeOption;
import 'ai_baholash_bundle.dart' show AiClientInfo, AiLocationInfo, AiRoom;

class Kadastr3dBundle {
  Kadastr3dBundle({
    required this.kadastr,
    this.client,
    this.location,
    this.objectType,
    this.floor,
    this.totalFloors,
    List<AiRoom>? rooms,
    List<String>? imageKeys,
    List<String>? kadastrKeys,
    List<String>? scanKeys,
  })  : rooms = rooms ?? <AiRoom>[],
        imageKeys = imageKeys ?? <String>[],
        kadastrKeys = kadastrKeys ?? <String>[],
        scanKeys = scanKeys ?? <String>[];

  final CadastreLookupResult kadastr;
  AiClientInfo? client;
  AiLocationInfo? location;

  /// turar/noturar/ombor/sanoat — chosen from the backend-provided, localized
  /// `GET /3d-kadastr-jobs/object-types` list (no longer a hardcoded enum).
  ObjectTypeOption? objectType;

  /// Which floor the object is on, and total floors in the building.
  int? floor;
  int? totalFloors;

  /// Optional dynamic room breakdown.
  final List<AiRoom> rooms;

  /// Object keys returned by `POST /3d-kadastr-jobs/upload`, per category.
  final List<String> imageKeys; // property photos (property_photo)
  final List<String> kadastrKeys; // kadastr docs (kadastr)
  final List<String> scanKeys; // LiDAR scan meshes (scan_3d)

  /// On-device file paths, index-aligned with the key lists above. Local-only
  /// (never serialized) — they let the intake step restore its upload tiles and
  /// power the full-screen preview gallery when the user re-enters the step.
  final List<String> imagePaths = [];
  final List<String> kadastrPaths = [];

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
        if (objectType != null) 'object_type': objectType!.value,
        if (floor != null) 'floor': floor,
        if (totalFloors != null) 'total_floors': totalFloors,
        if (rooms.isNotEmpty) 'rooms': rooms.map((r) => r.toJson()).toList(),
        if (imageKeys.isNotEmpty) 'image_keys': imageKeys,
        if (kadastrKeys.isNotEmpty) 'kadastr_keys': kadastrKeys,
        if (scanKeys.isNotEmpty) 'scan_keys': scanKeys,
      };
}
