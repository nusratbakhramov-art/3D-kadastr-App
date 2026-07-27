/// Xaritadan obyekt joylashuvini belgilash ekrani (flutter_map + OSM).
///
/// Foydalanuvchi xaritada **tap** qilgan joyga marker qo'yiladi. "Tasdiqlash"
/// bilan tanlangan `LatLng` qaytariladi. Default markaz Toshkent shahri.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../widgets/map_zoom_controls.dart';
import '../widgets/service_app_bar.dart';

class MapLocationPickerScreen extends StatefulWidget {
  const MapLocationPickerScreen({
    super.key,
    this.initialPoint,
    this.title,
    this.subtitle,
  });

  final LatLng? initialPoint;

  /// AppBar sarlavhasi; `null` bo'lsa joriy tilda 'Joyni tanlang'.
  final String? title;

  /// AppBar izohi; `null` bo'lsa joriy tilda standart matn ishlatiladi.
  final String? subtitle;

  @override
  State<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  // Toshkent markazi — default boshlanish nuqtasi.
  static const _defaultCenter = LatLng(41.2995, 69.2401);
  static const _defaultZoom = 12.5;

  late final MapController _controller;
  LatLng? _selected;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _controller = MapController();
    _selected = widget.initialPoint;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap(TapPosition _, LatLng point) {
    HapticFeedback.selectionClick();
    setState(() => _selected = point);
  }

  void _confirm() {
    if (_selected == null) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(_selected);
  }

  Future<void> _locateMe() async {
    if (_locating) return;
    final l = Localizations.localeOf(context);
    setState(() => _locating = true);
    try {
      // 1. Qurilmada geolokatsiya yoqilganmi?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError(tr(l, 'services.location.map.location_disabled'));
        return;
      }

      // 2. Ruxsat tekshirish va so'rash.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError(tr(l, 'services.location.map.permission_denied'));
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError(tr(l, 'services.location.map.permission_denied_forever'));
        return;
      }

      // 3. Joriy joylashuvni olish.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      if (!mounted) return;
      final point = LatLng(pos.latitude, pos.longitude);
      HapticFeedback.lightImpact();
      setState(() => _selected = point);
      _controller.move(point, 16);
    } catch (e) {
      _showError('${tr(l, 'services.location.map.locate_failed')}: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    AppToast.error(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: ServiceAppBar(
                title: widget.title ?? tr(l, 'services.location.map.title'),
                subtitle:
                    widget.subtitle ?? tr(l, 'services.location.map.subtitle'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: FlutterMap(
                      mapController: _controller,
                      options: MapOptions(
                        initialCenter: widget.initialPoint ?? _defaultCenter,
                        initialZoom: _defaultZoom,
                        minZoom: 4,
                        maxZoom: 18,
                        onTap: _onTap,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'uz.kadastr.kadastr',
                          maxZoom: 19,
                        ),
                        if (_selected != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _selected!,
                                width: 44,
                                height: 44,
                                alignment: Alignment.topCenter,
                                child: const _PinIcon(),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: MapZoomControls(controller: _controller),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _LocateMeFab(
                      busy: _locating,
                      onTap: _locateMe,
                    ),
                  ),
                  if (_selected != null)
                    Positioned(
                      left: 16,
                      right: 76, // FAB uchun joy qoldiramiz
                      bottom: 18,
                      child: _CoordsBadge(point: _selected!),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ListingCtaButton(
                label: _selected == null
                    ? tr(l, 'services.location.map.mark_first')
                    : tr(l, 'services.location.map.confirm'),
                enabled: _selected != null,
                onTap: _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinIcon extends StatelessWidget {
  const _PinIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.location_on,
      color: AppColors.splashGreen,
      size: 44,
      shadows: [
        Shadow(
          color: Colors.black54,
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    );
  }
}

class _LocateMeFab extends StatelessWidget {
  const _LocateMeFab({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final fg = AppColors.splashGreen;

    return Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.splashGreen,
                    ),
                  )
                : Icon(Icons.my_location, color: fg, size: 24),
          ),
        ),
      ),
    );
  }
}

class _CoordsBadge extends StatelessWidget {
  const _CoordsBadge({required this.point});
  final LatLng point;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.92);
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.place_outlined,
            size: 18,
            color: AppColors.splashGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'lat: ${point.latitude.toStringAsFixed(6)}, '
              'lon: ${point.longitude.toStringAsFixed(6)}',
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
