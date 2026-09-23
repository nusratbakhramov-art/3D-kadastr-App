/// Milliy geoportal (open.ngis.uz) kadastr qatlamlari — xaritada uchastka
/// chegaralarini chizish va bosilgan uydan kadastr raqamini olish.
///
/// Server — Kadastr agentligining ArcGIS REST servisi (`db.ngis.uz`);
/// open.ngis.uz ning o'zi ham aynan shundan o'qiydi (anonim o'qish ochiq).
///
/// ## Nega VEKTOR, rasm emas
///
/// Geoportal (va uning veb klonlari) chegaralarni `MapServer/export` orqali
/// KO'RINISH UCHUN BITTA PNG qilib oladi. Desktopda bu yaxshi ishlaydi, mobil
/// ilovada esa yomon: rasm faqat barmoq uzilgandan keyin so'raladi, kelguncha
/// eski rasm yangi ko'rinishga cho'zilib turadi, har bosishda esa kadastr
/// raqami uchun yana tarmoqqa chiqish kerak bo'ladi.
///
/// Shuning uchun bu yerda uchastkalar `FeatureServer/<n>/query` dan
/// **GeoJSON** bo'lib olinadi va qurilmada `PolygonLayer` bilan chiziladi:
/// - surish/masshtablashda qayta so'rov yo'q — chizma darhol qayta chiziladi;
/// - bosilgan uy qurilmaning o'zida topiladi — raqam bir zumda chiqadi;
/// - istalgan masshtabda aniq (rasm cho'zilib xiralashmaydi).
///
/// O'lchov (Toshkent, 800 m li kvadrat, LTE emas — Wi-Fi): turar 20 ta uchastka
/// ≈ 10 KB, noturar 47 ta ≈ 25 KB, xatlovsiz 479 ta ≈ 177 KB; javob 0.05–0.3 s.
///
/// ## Bbox uchun FeatureServer, nuqta uchun MapServer ham bo'ladi
///
/// `TURAR_UZKAD_DB16/MapServer/0/query` ga ENVELOPE berilsa bo'sh javob
/// qaytaradi (nuqta bilan esa ishlaydi) — shuning uchun ko'rinish so'rovlari
/// FAQAT `FeatureServer` ga boradi.
///
/// ## NIMA QAYTADI
///
/// Bu qatlamlarda faqat kadastr raqami va ma'muriy joylashuv (viloyat / tuman /
/// mahalla) ochiq. **Ko'cha manzili va obyekt maydoni bu yerda YO'Q** — ular
/// open.ngis.uz da ham OneID ortida. Shu sababli xarita faqat kadastr raqamini
/// beradi, manzil va maydon esa avvalgidek davreestr qidiruvidan
/// ([CadastreApiService.lookup]) keladi.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../cadastre_number.dart';

class NgisException implements Exception {
  const NgisException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'NgisException($code): $message';
}

/// Web Mercator'da 0-zoom masshtabi (96 dpi, 256 px tile).
///
/// ArcGIS qatlamlarning ko'rinish chegarasini MASSHTAB bilan beradi
/// (`minScale: 5198`), xaritada esa bizda zoom bor — [scaleToZoom] ko'prik.
const double _scaleAtZoom0 = 559082264.0287178;

/// ArcGIS `minScale` → xarita zoomi. Masshtab kichraygani sari zoom oshadi.
double scaleToZoom(double scale) =>
    scale <= 0 ? 0 : math.log(_scaleAtZoom0 / scale) / math.ln2;

/// Kadastr qatlami — geoportalning WebMap konfiguratsiyasidan olingan.
class NgisLayer {
  const NgisLayer({
    required this.id,
    required this.service,
    required this.featureLayer,
    required this.identifyLayer,
    required this.numberField,
    required this.placeFields,
    required this.minScale,
    required this.fill,
    required this.stroke,
  });

  /// Ichki id — tarjima kaliti sifatida ham ishlatiladi:
  /// `services.ai.parcel.layer.<id>`.
  final String id;

  /// ARCGIS ildizidan keyingi servis yo'li.
  final String service;

  /// Ko'rinish (bbox) so'rovi uchun qatlam yo'li — har doim `FeatureServer/<n>`.
  final String featureLayer;

  /// Nuqta bo'yicha qidiruv uchun qatlam yo'li.
  final String identifyLayer;

  /// Kadastr raqami saqlanadigan maydon — qatlamdan qatlamga farq qiladi.
  final String numberField;

  /// Ma'muriy joylashuv maydonlari (viloyat / tuman / mahalla), shu tartibda.
  final List<String> placeFields;

  /// Qatlam shu masshtabdan uzoqlashganda chizilmaydi (geoportaldagi qiymat).
  ///
  /// Chegara bejiz emas: xatlovsiz qatlamda 800 m li kvadratda 479 ta uchastka
  /// bor — uzoqroqdan chizilsa bu minglab poligonga aylanadi.
  final double minScale;

  /// To'ldirish va kontur ranglari — geoportalning o'z `drawingInfo` sidan.
  final Color fill;
  final Color stroke;

  /// Chizish uchun eng kichik zoom.
  double get minZoom => scaleToZoom(minScale);

  String get _root => NgisParcelClient.root;
  Uri get boundsQueryUrl => Uri.parse('$_root/$service/$featureLayer/query');
  Uri get identifyQueryUrl => Uri.parse('$_root/$service/$identifyLayer/query');

  /// So'raladigan maydonlar ro'yxati.
  String get outFields => [numberField, ...placeFields].join(',');
}

/// Baholash uchun ma'noli qatlamlar — USTIGA CHIZILISH tartibida
/// (birinchisi eng pastda, oxirgisi eng ustida).
///
/// Tartib bejiz: bir nuqtada bir nechta uchastka ustma-ust tushsa, ustidagisi
/// aniqroq (turar-joy hovlisi qishloq xo'jaligi massividan aniqroq), shuning
/// uchun bosilganda ham birinchi bo'lib o'sha taklif qilinadi.
///
/// Geoportalda 17 ta qatlam bor (o'rmon, suv, avtoyul, zaxira…), lekin
/// ko'chmas mulk baholashda ular uchramaydi — ro'yxat to'rttasi bilan
/// cheklangan.
const List<NgisLayer> kNgisParcelLayers = [
  // Qishloq xo'jaligi — eng katta konturlar, eng pastda.
  NgisLayer(
    id: 'qishloq',
    service: 'UZKAD/AGR_ONLY_UZKAD_DB16',
    featureLayer: 'FeatureServer/0',
    identifyLayer: 'MapServer/0',
    numberField: 'cadastral_number',
    placeFields: ['region_name', 'district_name', 'mahalla_name'],
    minScale: 37944.714845,
    fill: Color(0x4093F263),
    stroke: Color(0xFF4A7A2E),
  ),
  // Xatlovdan o'tkazilmagan turar-joy yerlar — mahallalardagi hovlilarning
  // KO'PCHILIGI aynan shu qatlamda. Avval umuman chizilmasdi, "uy bor, lekin
  // xarita bo'sh" degan holatning asosiy sababi shu edi.
  NgisLayer(
    id: 'xatlovsiz',
    service: 'Hosted/DKYAT_2023',
    featureLayer: 'FeatureServer/0',
    identifyLayer: 'MapServer/2',
    numberField: 'kadastr',
    placeFields: ['viloyat', 'tuman'],
    minScale: 7115.553407,
    fill: Color(0x40E8DC7D),
    stroke: Color(0xF2FFFFFF),
  ),
  NgisLayer(
    id: 'noturar',
    service: 'UZKAD/NOTURAR_UZKAD_DB16',
    featureLayer: 'FeatureServer/0',
    identifyLayer: 'MapServer/0',
    numberField: 'cadastral_number',
    placeFields: ['region_name', 'district_name', 'mahalla_name'],
    minScale: 14901.647919,
    fill: Color(0x6EAB6709),
    stroke: Color(0xFFF0B040),
  ),
  // Turar-joy — eng ustida: hovli bosilganda birinchi bo'lib shu chiqadi.
  NgisLayer(
    id: 'turar',
    service: 'UZKAD/TURAR_UZKAD_DB16',
    featureLayer: 'FeatureServer/0',
    identifyLayer: 'MapServer/0',
    numberField: 'cadastral_number',
    placeFields: ['region_name', 'district_name', 'mahalla_name'],
    minScale: 5198.278858,
    fill: Color(0x5C453D03),
    stroke: Color(0xFFF0F075),
  ),
];

/// Nuqta bo'yicha qidirishda ustuvorlik tartibi — chizish tartibining teskarisi
/// (eng ustidagi qatlam birinchi so'raladi).
final List<NgisLayer> kNgisIdentifyOrder =
    kNgisParcelLayers.reversed.toList(growable: false);


/// Xaritadan topilgan bitta kadastr obyekti.
class NgisParcel {
  const NgisParcel({
    required this.cadastreNumber,
    required this.layerId,
    this.regionName,
    this.districtName,
    this.mahallaName,
    this.propertyKind,
    this.parts = const [],
  });

  final String cadastreNumber;

  /// Qaysi qatlamdan topilgani ([NgisLayer.id]).
  final String layerId;

  final String? regionName;
  final String? districtName;
  final String? mahallaName;

  /// `prop_kind_private_house` kabi tur kodi — ro'yxatda ajratish uchun.
  final String? propertyKind;

  /// Uchastka konturlari. Odatda bitta, lekin bo'lingan uchastka bir necha
  /// bo'lakdan iborat bo'lishi mumkin (GeoJSON `MultiPolygon`).
  final List<List<LatLng>> parts;

  /// Eng katta bo'lakning tashqi konturi — ajratib ko'rsatish uchun.
  List<LatLng> get outline {
    if (parts.isEmpty) return const [];
    var best = parts.first;
    for (final part in parts) {
      if (part.length > best.length) best = part;
    }
    return best;
  }

  /// Ma'muriy joylashuv: "Toshkent shahri, Sirg'ali tumani, Ko'hna Qumariq MFY".
  ///
  /// Bu KO'CHA MANZILI EMAS — geoportalning ochiq qatlamida manzil yo'q. Faqat
  /// tanlashda "shu joymi?" deb tasdiqlash uchun ko'rsatiladi.
  String get placeLabel => [
        regionName,
        districtName,
        mahallaName,
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

  /// Chegaraning taxminiy markazi — xaritani shu joyga olib borish uchun.
  LatLng? get center {
    final ring = outline;
    if (ring.isEmpty) return null;
    var lat = 0.0;
    var lng = 0.0;
    for (final p in ring) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / ring.length, lng / ring.length);
  }

  /// Joylashuv nomlari bo'sh kelgan bo'lsa — ularni [other] dan to'ldiradi.
  ///
  /// Ko'rinish so'rovi tez bo'lishi uchun kam maydon so'raladi; bosilgandan
  /// keyin fonda to'liq yozuv olinadi va shu yerda ustiga qo'yiladi.
  NgisParcel mergePlace(NgisParcel other) => NgisParcel(
        cadastreNumber: cadastreNumber,
        layerId: layerId,
        regionName: regionName ?? other.regionName,
        districtName: districtName ?? other.districtName,
        mahallaName: mahallaName ?? other.mahallaName,
        propertyKind: propertyKind ?? other.propertyKind,
        parts: parts.isNotEmpty ? parts : other.parts,
      );

  /// Tenglik raqam + qatlam bo'yicha: `PolygonLayer` bitta uchastkaning har bir
  /// bo'lagini alohida poligon qilib chizadi, bosilganda esa ular bitta obyekt
  /// sifatida qaytishi kerak.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NgisParcel &&
          other.cadastreNumber == cadastreNumber &&
          other.layerId == layerId;

  @override
  int get hashCode => Object.hash(cadastreNumber, layerId);
}

class NgisParcelClient {
  NgisParcelClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String root = 'https://db.ngis.uz/db/rest/services';

  /// Bitta so'rovda olinadigan uchastkalar chegarasi.
  ///
  /// Servisning o'z chegarasi 2000 ta; undan pastroq olamiz, chunki ekranga
  /// mingdan ortiq poligon chizish baribir ma'nosiz va sekin.
  static const int maxFeatures = 1200;

  /// Geometriyani soddalashtirish qadami (gradusda) ≈ 0.22 m.
  ///
  /// Eng katta masshtabda ham piksel yarmidan kichik — ko'zga ko'rinmaydi,
  /// lekin javobni sezilarli qisqartiradi.
  static const String _simplifyOffset = '0.000002';

  void dispose() => _client.close();

  /// Berilgan ko'rinishdagi uchastkalarni bitta qatlamdan oladi.
  ///
  /// Javob GeoJSON — `f=geojson`; ArcGIS ni o'z `rings` formatidan o'girish
  /// shart emas va javob ham ixchamroq.
  Future<List<NgisParcel>> parcelsInBounds(
    NgisLayer layer,
    LatLngBounds bounds,
  ) async {
    final body = <String, String>{
      'geometry': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
      'geometryType': 'esriGeometryEnvelope',
      'inSR': '4326',
      'outSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': layer.outFields,
      'returnGeometry': 'true',
      // 6 xona ≈ 11 sm — kadastr chegarasi uchun ortig'i bilan yetadi.
      'geometryPrecision': '6',
      'maxAllowableOffset': _simplifyOffset,
      'resultRecordCount': '$maxFeatures',
      'f': 'geojson',
    };

    return _geoJsonParcels(layer, await _post(layer.boundsQueryUrl, body));
  }

  /// Kadastr RAQAMI bo'yicha uchastkani topadi — foydalanuvchi raqamni QO'LDA
  /// kiritganda.
  ///
  /// Nega kerak: reyestr javobida koordinata YO'Q (`CadastreLookupResult` da
  /// lat/lng maydoni yo'q), shuning uchun raqamni qo'lda kiritgan odamdan
  /// keyingi qadamda uyni yana xaritada belgilash so'ralardi — garchi uchastka
  /// geoportalda turgan bo'lsa ham. Bu yerda o'sha nuqtani raqamning o'zidan
  /// olamiz.
  ///
  /// Qatlamlar PARALLEL so'raladi, javob esa [kNgisIdentifyOrder] ustuvorligi
  /// bo'yicha tanlanadi (turar-joy qishloq xo'jaligidan aniqroq). Bittasining
  /// yiqilishi qolganini to'xtatmaydi.
  ///
  /// Topilmasa `null` — bu XATO EMAS: qatlamda yo'q uchastkalar bor va u holda
  /// oqim avvalgidek qo'lda xarita qadamiga tushadi.
  Future<NgisParcel?> findByNumber(String cadastreNumber) async {
    final full = cadastreNumber.trim();
    if (full.isEmpty) return null;
    final base = cadastreBaseNumber(full);
    // Avval raqamning o'zi: qatlamda aynan shu yozuv bo'lsa, uni olamiz.
    // Dumsiz asos faqat farq qilganda ikkinchi urinish bo'ladi.
    final candidates = <String>[full, if (base != full) base];

    for (final number in candidates) {
      final results = await Future.wait(
        kNgisIdentifyOrder.map(
          (layer) => _queryByNumber(layer, number).catchError(
            (_) => const <NgisParcel>[],
          ),
        ),
      );
      for (final list in results) {
        if (list.isNotEmpty) return list.first;
      }
    }
    return null;
  }

  Future<List<NgisParcel>> _queryByNumber(
    NgisLayer layer,
    String number,
  ) async {
    final decoded = await _post(layer.boundsQueryUrl, {
      // Apostrof SQL ni buzmasligi uchun ikkilantiriladi. Raqamda uchramaydi,
      // lekin bu yerga maydon matni ham tushishi mumkin.
      'where': "${layer.numberField} = '${number.replaceAll("'", "''")}'",
      'outFields': layer.outFields,
      'outSR': '4326',
      'returnGeometry': 'true',
      'geometryPrecision': '6',
      'maxAllowableOffset': _simplifyOffset,
      // Bo'lingan uchastka bir necha yozuv bo'lishi mumkin — birinchisi
      // yetadi, lekin javobni cheklab qo'yamiz.
      'resultRecordCount': '4',
      'f': 'geojson',
    });
    return _geoJsonParcels(layer, decoded);
  }

  List<NgisParcel> _geoJsonParcels(
    NgisLayer layer,
    Map<dynamic, dynamic>? decoded,
  ) {
    if (decoded == null) return const [];

    final features = decoded['features'];
    if (features is! List) return const [];

    final out = <NgisParcel>[];
    for (final f in features.whereType<Map>()) {
      final props = (f['properties'] as Map?) ?? const {};
      final number = _text(props[layer.numberField]);
      if (number == null) continue;
      final parts = _geoJsonParts(f['geometry']);
      if (parts.isEmpty) continue;
      out.add(_parcel(layer, number, props, parts));
    }
    return out;
  }

  /// Bosilgan nuqtadagi BARCHA uchastkalarni qaytaradi.
  ///
  /// Odatda kerak emas — uchastkalar allaqachon qurilmada bo'lgani uchun
  /// bosish tarmoqsiz hal bo'ladi. Bu yo'l ikki holatda ishlaydi: qatlam hali
  /// yuklanmagan bo'lsa va bosilgan joy uzoqroq masshtabda bo'lsa (chegara
  /// chizilmagan, lekin uchastka bor).
  ///
  /// Qatlamlar PARALLEL so'raladi va bittasining yiqilishi qolganini
  /// to'xtatmaydi — yarim natija hech qanday natijadan yaxshi.
  Future<List<NgisParcel>> identifyAt(LatLng point) async {
    final results = await Future.wait(
      kNgisIdentifyOrder.map(
        (layer) => _identifyLayer(layer, point).catchError(
          (_) => const <NgisParcel>[],
        ),
      ),
    );

    // Bir xil raqam ikki qatlamda uchrashi mumkin — birinchisi (ustuvorroq
    // qatlam) qoladi.
    final seen = <String>{};
    final out = <NgisParcel>[];
    for (final parcel in results.expand((e) => e)) {
      if (seen.add(parcel.cadastreNumber)) out.add(parcel);
    }
    return out;
  }

  /// Bitta uchastkaning to'liq yozuvini oladi — ro'yxatda joylashuv ko'rsatish
  /// uchun. Topilmasa `null`.
  Future<NgisParcel?> details(NgisParcel parcel) async {
    final layer = kNgisParcelLayers.where((l) => l.id == parcel.layerId);
    if (layer.isEmpty) return null;
    final center = parcel.center;
    if (center == null) return null;
    try {
      final found = await _identifyLayer(layer.first, center);
      for (final p in found) {
        if (p.cadastreNumber == parcel.cadastreNumber) return p;
      }
    } on NgisException {
      return null;
    }
    return null;
  }

  Future<List<NgisParcel>> _identifyLayer(NgisLayer layer, LatLng point) async {
    final decoded = await _post(layer.identifyQueryUrl, {
      'geometry': jsonEncode({'x': point.longitude, 'y': point.latitude}),
      'geometryType': 'esriGeometryPoint',
      'inSR': '4326',
      'outSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': '*',
      'returnGeometry': 'true',
      // Bitta qatlamda ham bir necha uchastka ustma-ust tushishi mumkin
      // (bo'lingan hovli) — bittasi bilan cheklanmaymiz.
      'resultRecordCount': '4',
      'f': 'json',
    });
    if (decoded == null) return const [];

    final features = decoded['features'];
    if (features is! List) return const [];

    final out = <NgisParcel>[];
    for (final f in features.whereType<Map>()) {
      final attrs = (f['attributes'] as Map?) ?? const {};
      final number = _text(attrs[layer.numberField]);
      if (number == null) continue;
      out.add(_parcel(layer, number, attrs, _esriParts(f['geometry'])));
    }
    return out;
  }

  NgisParcel _parcel(
    NgisLayer layer,
    String number,
    Map<dynamic, dynamic> attrs,
    List<List<LatLng>> parts,
  ) {
    final place = layer.placeFields;
    return NgisParcel(
      cadastreNumber: number,
      layerId: layer.id,
      regionName: place.isNotEmpty ? _text(attrs[place[0]]) : null,
      districtName: place.length > 1 ? _text(attrs[place[1]]) : null,
      mahallaName: place.length > 2 ? _text(attrs[place[2]]) : null,
      propertyKind: _text(attrs['property_kind']),
      parts: parts,
    );
  }

  /// ArcGIS `error` ni HTTP 200 ichida ham qaytaradi — shuning uchun javob shu
  /// yerda markazlashgan holda tekshiriladi. Xato bo'lsa `null`.
  Future<Map<dynamic, dynamic>?> _post(
    Uri uri,
    Map<String, String> body,
  ) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const NgisException('TIMEOUT', 'Geoportal javob bermadi');
    } on SocketException catch (e) {
      throw NgisException('NETWORK', e.message);
    } on http.ClientException catch (e) {
      throw NgisException('NETWORK', e.message);
    }
    if (res.statusCode != 200) {
      throw NgisException('HTTP_${res.statusCode}', 'Geoportal xatosi');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) return null;
    if (decoded['error'] != null) return null;
    return decoded;
  }

  static String? _text(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  /// GeoJSON `Polygon` / `MultiPolygon` dan tashqi konturlarni oladi.
  static List<List<LatLng>> _geoJsonParts(Object? geometry) {
    if (geometry is! Map) return const [];
    final coords = geometry['coordinates'];
    if (coords is! List || coords.isEmpty) return const [];

    switch (geometry['type']) {
      case 'Polygon':
        final ring = _ring(coords.first);
        return ring.isEmpty ? const [] : [ring];
      case 'MultiPolygon':
        final out = <List<LatLng>>[];
        for (final polygon in coords) {
          if (polygon is! List || polygon.isEmpty) continue;
          final ring = _ring(polygon.first);
          if (ring.isNotEmpty) out.add(ring);
        }
        return out;
      default:
        return const [];
    }
  }

  /// Esri `rings` dan konturlarni oladi (`[[[lng, lat], …], …]`).
  ///
  /// Ichki teshiklar (soat strelkasiga teskari ringlar) ham shu yerga tushadi,
  /// lekin ular kam uchraydi va to'ldirish yarim shaffof — ajratib o'tirilmaydi.
  static List<List<LatLng>> _esriParts(Object? geometry) {
    if (geometry is! Map) return const [];
    final rings = geometry['rings'];
    if (rings is! List) return const [];
    final out = <List<LatLng>>[];
    for (final ring in rings) {
      final points = _ring(ring);
      if (points.isNotEmpty) out.add(points);
    }
    return out;
  }

  static List<LatLng> _ring(Object? ring) {
    if (ring is! List) return const [];
    final out = <LatLng>[];
    for (final p in ring) {
      if (p is List && p.length >= 2) {
        final lng = (p[0] as num?)?.toDouble();
        final lat = (p[1] as num?)?.toDouble();
        if (lng != null && lat != null) out.add(LatLng(lat, lng));
      }
    }
    return out;
  }
}
