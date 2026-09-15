/// E'lon sahifasidagi joylashuv xaritasi.
///
/// Ikki narsani ko'rsatadi: obyekt nuqtasi va — geoportaldan tanlangan
/// bo'lsa — UCHASTKA CHEGARASI. Chegara xaritani e'lon uchun ma'noli
/// qiladi: xaridor «qayerda» dan tashqari «qancha joy» ni ham ko'radi.
///
/// Xarita ATAYLAB surilmaydi (`InteractiveFlag.none`): u ro'yxat ichida
/// turibdi va surish ro'yxatning vertikal siljishini o'g'irlab, sahifani
/// "yopishqoq" qilib qo'yardi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/app_colors.dart';
import '../../services/widgets/parcel_basemap.dart';
import '../models/parcel_boundary.dart';

class ListingLocationMap extends StatelessWidget {
  const ListingLocationMap({
    super.key,
    this.point,
    this.boundary,
    this.height = 190,
  });

  final LatLng? point;
  final ParcelBoundary? boundary;
  final double height;

  /// Chegara ham, nuqta ham bo'lmasa ko'rsatadigan narsa yo'q.
  bool get _hasSomethingToShow => point != null || boundary != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasSomethingToShow) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final center = boundary?.center ?? point!;
    // Chegara bor bo'lsa uchastka ekranga sig'sin; yolg'iz nuqtada esa
    // ko'cha ko'rinadigan masshtab.
    final zoom = boundary != null ? 17.5 : 16.0;
    final rings = boundary?.parts ?? const <List<LatLng>>[];

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IgnorePointer(
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: ParcelBasemap.satellite.urlTemplate,
              maxNativeZoom: ParcelBasemap.satellite.maxNativeZoom,
              maxZoom: 20,
              tileProvider: CachedTileProvider(),
              // Esri talabi — atribut xarita ustida ko'rinib turadi.
              userAgentPackageName: 'uz.kadastr.app',
            ),
            if (rings.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final ring in rings)
                    Polygon(
                      points: ring,
                      borderColor: AppColors.splashGreen,
                      borderStrokeWidth: 2.5,
                      color: AppColors.splashGreen.withValues(alpha: 0.22),
                    ),
                ],
              ),
            // Chegara bor bo'lsa metka ATAYLAB chizilmaydi: u chegarani
            // yopib, uchastkaning shaklini ko'rsatmay qo'yardi.
            if (point != null && rings.isEmpty)
              MarkerLayer(
                markers: [
                  Marker(
                    point: point!,
                    width: 34,
                    height: 34,
                    child: const Icon(
                      Icons.place_rounded,
                      size: 34,
                      color: AppColors.declineRed,
                    ),
                  ),
                ],
              ),
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: _Attribution(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text(
        ParcelBasemap.satellite.attribution,
        style: const TextStyle(
          fontFamily: 'MTSText',
          fontSize: 9,
          color: Colors.white,
        ),
      ),
    );
  }
}
