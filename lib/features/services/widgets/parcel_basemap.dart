/// Kadastr xaritasi uchun asos qatlamlar (basemap) va ularning tile keshi.
///
/// ## Nega sun'iy yo'ldosh
///
/// open.ngis.uz da asos qatlam — sun'iy yo'ldosh tasviri, va uning "sifatli"
/// ko'rinishining yarmi aynan shundan. OpenStreetMap sxemasida O'zbekistonning
/// ko'p mahallasida uy konturi umuman chizilmagan: foydalanuvchi bo'sh oq
/// maydonni ko'radi va o'z uyini topa olmaydi. Sun'iy yo'ldoshda esa u o'z
/// tomini taniydi va aynan uning ustiga bosadi.
///
/// ## Nega Esri, Google emas
///
/// Geoportal `mt0.google.com/vt` dan foydalanadi — bu Google Maps Platform
/// shartnomasidan tashqaridagi yo'l va uni ilovaga ko'chirish litsenziya
/// muammosi. [ParcelBasemap.satellite] o'rniga Esri World Imagery ishlatiladi:
/// Toshkent bo'yicha aniqligi amalda bir xil (z19 gacha), atribut ko'rsatilsa
/// ochiq foydalanish mumkin. Mapbox / MapTiler / Google Maps SDK ga o'tish
/// kerak bo'lsa — [ParcelBasemap] ga bitta yozuv qo'shish kifoya, qolgan kod
/// tegilmaydi.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';

/// Asos qatlam turlari — geoportaldagi "Sputnik" va "Sxema" ga mos.
enum ParcelBasemapKind { satellite, scheme }

@immutable
class ParcelBasemap {
  const ParcelBasemap({
    required this.kind,
    required this.urlTemplate,
    required this.attribution,
    required this.maxNativeZoom,
  });

  final ParcelBasemapKind kind;
  final String urlTemplate;

  /// Xarita burchagida ko'rsatiladigan manba yozuvi — provayder talabi.
  final String attribution;

  /// Serverda mavjud eng katta masshtab. Undan yaqinroqda tile'lar cho'ziladi
  /// (`maxZoom` kattaroq) — uchastka mayda bo'lsa aniq bosish uchun kerak.
  final int maxNativeZoom;

  /// Sun'iy yo'ldosh — Esri World Imagery. Toshkentda z19 gacha haqiqiy tasvir.
  static const ParcelBasemap satellite = ParcelBasemap(
    kind: ParcelBasemapKind.satellite,
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/'
        'MapServer/tile/{z}/{y}/{x}',
    attribution: '© Esri, Maxar, Earthstar Geographics',
    maxNativeZoom: 19,
  );

  /// Sxema — ilovaning boshqa xaritalari bilan bir xil OSM.
  static const ParcelBasemap scheme = ParcelBasemap(
    kind: ParcelBasemapKind.scheme,
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap',
    maxNativeZoom: 19,
  );

  static const List<ParcelBasemap> all = [satellite, scheme];

  ParcelBasemap get other =>
      kind == ParcelBasemapKind.satellite ? scheme : satellite;
}

/// Tile'lar uchun alohida disk keshi.
///
/// Ilovaning umumiy rasm keshidan ajratilgan: bitta ekran ~20 ta tile, va
/// standart keshning 200 obyektlik chegarasi bir necha surishdayoq avatarlar
/// bilan uy suratlarini siqib chiqarardi. Bu yerda chegara kattaroq va muddat
/// uzunroq — sun'iy yo'ldosh tasviri tez-tez o'zgarmaydi.
class ParcelTileCache {
  ParcelTileCache._();

  static const String key = 'ngis_map_tiles';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 3000,
    ),
  );
}

/// Tile'larni diskdan beradigan provayder.
///
/// `flutter_map` ning standart provayderi har safar tarmoqqa chiqadi: bitta
/// ekranni qayta ochish yana ~20 ta so'rov degani. Kesh bilan takroriy
/// ko'rinishlar bir zumda chiziladi va mobil trafik tejaladi.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedNetworkImageProvider(
        getTileUrl(coordinates, options),
        cacheManager: ParcelTileCache.instance,
        headers: headers,
      );
}
