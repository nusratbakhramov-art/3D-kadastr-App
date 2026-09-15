/// E'longa biriktirilgan uchastka chegarasi.
///
/// Geoportaldan (NGIS) tanlangan uchastkaning konturi. Saqlash shakli —
/// GeoJSON `MultiPolygon`, chunki bo'lingan uchastka bir necha bo'lakdan
/// iborat bo'lishi mumkin va backend ustuni aynan shu shaklni kutadi
/// (`app/schemas/bozor_listing.py` dagi `_validate_boundary`).
///
/// ⚠️ GeoJSON nuqtasi `[lng, lat]` tartibida — `LatLng` ning teskarisi.
/// Ikkalasini chalkashtirish xatosi JIMGINA bo'ladi: chegara Toshkent
/// o'rniga Hind okeanida chiziladi. Shu sababli almashtirish FAQAT shu
/// faylda, ikkita joyda amalga oshiriladi.
library;

import 'package:latlong2/latlong.dart';

class ParcelBoundary {
  const ParcelBoundary(this.parts);

  /// Uchastka bo'laklari; har biri — tashqi kontur nuqtalari.
  final List<List<LatLng>> parts;

  /// Backend qabul qiladigan eng ko'p nuqta (`_MAX_BOUNDARY_POINTS`).
  ///
  /// Bu yerda ham bor, chunki chegarani KESISH klientda bo'lishi kerak:
  /// aks holda yirik uchastkali e'lon yuborishda 422 chiqib, foydalanuvchi
  /// tuzata olmaydigan xatoga urilardi.
  static const int maxPoints = 4000;

  /// Halqada saqlanishi shart bo'lgan eng kam nuqta — undan kami yuza emas,
  /// chiziq.
  static const int _minRingPoints = 3;

  bool get isEmpty => parts.every((p) => p.length < _minRingPoints);

  int get pointCount =>
      parts.fold<int>(0, (sum, part) => sum + part.length);

  /// Eng katta bo'lakning taxminiy markazi — xaritani shu joyga olib borish
  /// uchun.
  LatLng? get center {
    final ring = _largestPart;
    if (ring == null) return null;
    var lat = 0.0;
    var lng = 0.0;
    for (final p in ring) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / ring.length, lng / ring.length);
  }

  List<LatLng>? get _largestPart {
    List<LatLng>? best;
    for (final part in parts) {
      if (part.length < _minRingPoints) continue;
      if (best == null || part.length > best.length) best = part;
    }
    return best;
  }

  /// Uchastka konturlaridan chegara quradi. Nuqtalar soni [maxPoints] dan
  /// oshsa — bir tekisda siyraklashtiriladi (shakl saqlanadi, tafsilot
  /// kamayadi).
  static ParcelBoundary? fromRings(List<List<LatLng>> rings) {
    final kept = [
      for (final r in rings)
        if (r.length >= _minRingPoints) List<LatLng>.unmodifiable(r),
    ];
    if (kept.isEmpty) return null;
    return ParcelBoundary(List.unmodifiable(_thin(kept)));
  }

  /// GeoJSON `MultiPolygon` dan o'qiydi. Shakl kutilganidek bo'lmasa `null` —
  /// e'lon sahifasi chegarasiz ochilaveradi, yiqilmaydi.
  static ParcelBoundary? fromGeoJson(Object? json) {
    if (json is! Map) return null;
    if (json['type'] != 'MultiPolygon') return null;
    final coordinates = json['coordinates'];
    if (coordinates is! List) return null;

    final parts = <List<LatLng>>[];
    for (final polygon in coordinates) {
      if (polygon is! List || polygon.isEmpty) continue;
      // Faqat TASHQI halqa o'qiladi: ichki teshiklar (`polygon[1..]`) NGIS
      // uchastkalarida uchramaydi va ularni chizish uchun alohida kod kerak
      // bo'lardi.
      final ring = polygon.first;
      if (ring is! List) continue;
      final points = <LatLng>[];
      for (final point in ring) {
        if (point is! List || point.length < 2) continue;
        final lng = (point[0] as num?)?.toDouble();
        final lat = (point[1] as num?)?.toDouble();
        if (lng == null || lat == null) continue;
        points.add(LatLng(lat, lng));
      }
      if (points.length >= _minRingPoints) parts.add(points);
    }
    if (parts.isEmpty) return null;
    return ParcelBoundary(List.unmodifiable(parts));
  }

  /// Backend kutgan GeoJSON. Halqa OCHIQ yuboriladi — yopishni backend
  /// o'zi bajaradi (`_validate_boundary`), shunda yopish qoidasi bitta
  /// joyda qoladi.
  Map<String, dynamic> toGeoJson() => {
    'type': 'MultiPolygon',
    'coordinates': [
      for (final part in parts)
        [
          [
            for (final p in part) [p.longitude, p.latitude],
          ],
        ],
    ],
  };

  /// Nuqtalarni [maxPoints] ga sig'diradi: har bo'lakdan bir tekisda tanlab
  /// oladi, halqaning boshi va oxiri saqlanadi.
  static List<List<LatLng>> _thin(List<List<LatLng>> parts) {
    final total = parts.fold<int>(0, (s, p) => s + p.length);
    if (total <= maxPoints) return parts;

    // Har bo'lakdan qancha nuqta qoldirish kerakligi — hozirgi ulushiga
    // mutanosib, lekin halqa hech qachon uchburchakdan kichik bo'lmaydi.
    final result = <List<LatLng>>[];
    for (final part in parts) {
      final share = (part.length / total * maxPoints).floor();
      final target = share < _minRingPoints ? _minRingPoints : share;
      if (part.length <= target) {
        result.add(part);
        continue;
      }
      final step = part.length / target;
      final thinned = <LatLng>[
        for (var i = 0; i < target; i++) part[(i * step).floor()],
      ];
      result.add(List<LatLng>.unmodifiable(thinned));
    }
    return result;
  }
}
