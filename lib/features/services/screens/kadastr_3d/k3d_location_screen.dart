/// Step 2 of 3D Kadastr — pick the property's location on a map.
///
/// Identical UX to AI Baholash's location step (`ai_location_screen.dart`):
///   - Pin always at the map center; panning updates lat/lng.
///   - Search input with autocomplete → tap → map flies there.
///   - On settle, reverse-geocode and show the address; Confirm proceeds.
///
/// Unlike the old tap-to-drop modal picker, this is a normal forward wizard
/// step — it pushes the next screen instead of popping a result, so the
/// transition animates left-to-right like every other step.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/i18n.dart';
import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../../widgets/app_toast.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/geocoder_client.dart';
import '../../models/ai_baholash_bundle.dart' show AiLocationInfo;
import '../../models/kadastr_3d_bundle.dart';
import '../../widgets/map_zoom_controls.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';
import '../scan_object_type_screen.dart';

class K3dLocationScreen extends StatefulWidget {
  const K3dLocationScreen({super.key, required this.bundle});

  final Kadastr3dBundle bundle;

  @override
  State<K3dLocationScreen> createState() => _K3dLocationScreenState();
}

class _K3dLocationScreenState extends State<K3dLocationScreen> {
  static const _defaultCenter = LatLng(41.2995, 69.2401);
  static const _defaultZoom = 13.5;

  late final MapController _mapController;
  late final GeocoderClient _geocoder;
  final TextEditingController _searchCtrl = TextEditingController();

  late LatLng _center;

  // Search state.
  List<GeoSuggestion> _suggestions = const [];
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _searching = false;
  bool _suppressSearch = false;

  // Reverse-geocode state.
  String? _addressText;
  bool _resolving = false;
  Timer? _reverseDebounce;
  int _reverseRequestId = 0;

  // Current-location (geolocator) state.
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _geocoder = GeocoderClient();
    // Restore a previously confirmed location when stepping back into this
    // screen; otherwise start at the Tashkent default.
    final existing = widget.bundle.location;
    _center = existing != null
        ? LatLng(existing.lat, existing.lng)
        : _defaultCenter;
    _addressText = existing?.addressText;
    _searchCtrl.addListener(_onSearchChanged);
    _scheduleReverse();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    _geocoder.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ── Search (autocomplete) ────────────────────────────────────────────

  void _onSearchChanged() {
    if (_suppressSearch) return;
    _searchDebounce?.cancel();
    final q = _searchCtrl.text.trim();
    if (q.length < 3) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String q) async {
    final id = ++_searchRequestId;
    setState(() => _searching = true);
    try {
      final results = await _geocoder.autocomplete(q);
      if (!mounted || id != _searchRequestId) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    } on GeocoderException catch (e) {
      if (!mounted || id != _searchRequestId) return;
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      AppToast.error(context, e.message);
    } catch (_) {
      if (!mounted || id != _searchRequestId) return;
      setState(() => _searching = false);
    }
  }

  void _pickSuggestion(GeoSuggestion s) {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    _searchDebounce?.cancel();
    _searchRequestId++;
    _suppressSearch = true;
    _searchCtrl.value = TextEditingValue(
      text: s.name,
      selection: TextSelection.collapsed(offset: s.name.length),
    );
    _suppressSearch = false;
    setState(() {
      _suggestions = const [];
      _center = LatLng(s.lat, s.lng);
      _addressText =
          s.description.isEmpty ? s.name : '${s.name}, ${s.description}';
    });
    _mapController.move(_center, 17);
    _scheduleReverse();
  }

  // ── Reverse geocoding ────────────────────────────────────────────────

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd ||
        event is MapEventScrollWheelZoom) {
      final c = _mapController.camera.center;
      if (c.latitude == _center.latitude && c.longitude == _center.longitude) {
        return;
      }
      setState(() => _center = c);
      _scheduleReverse();
    }
  }

  void _scheduleReverse() {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 350), _runReverse);
  }

  Future<void> _runReverse() async {
    final id = ++_reverseRequestId;
    final c = _center;
    setState(() => _resolving = true);
    try {
      final text = await _geocoder.reverse(c.latitude, c.longitude);
      if (!mounted || id != _reverseRequestId) return;
      setState(() {
        _addressText = text;
        _resolving = false;
      });
    } on GeocoderException catch (_) {
      if (!mounted || id != _reverseRequestId) return;
      setState(() => _resolving = false);
    } catch (_) {
      if (!mounted || id != _reverseRequestId) return;
      setState(() => _resolving = false);
    }
  }

  // ── Current location ─────────────────────────────────────────────────

  Future<void> _goToCurrentLocation() async {
    HapticFeedback.lightImpact();
    final l = Localizations.localeOf(context);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          AppToast.error(context, tr(l, 'services.k3d.location.location_off'));
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          AppToast.error(
              context, tr(l, 'services.k3d.location.location_denied'));
        }
        return;
      }
      setState(() => _locating = true);
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = here;
        _locating = false;
      });
      _mapController.move(here, 17);
      _scheduleReverse();
    } catch (_) {
      if (!mounted) return;
      setState(() => _locating = false);
      AppToast.error(context, tr(l, 'services.k3d.location.location_error'));
    }
  }

  // ── Confirm / next ───────────────────────────────────────────────────

  void _confirm() {
    HapticFeedback.lightImpact();
    widget.bundle.location = AiLocationInfo(
      lat: _center.latitude,
      lng: _center.longitude,
      addressText: _addressText ?? widget.bundle.kadastr.address,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanObjectTypeScreen(bundle: widget.bundle),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

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
                title: tr(l, 'services.k3d.location.appbar'),
                subtitle: tr(l, 'services.k3d.location.subtitle'),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: StepProgressBar(count: 6, activeIndex: 2),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SearchInput(
                controller: _searchCtrl,
                isDark: isDark,
                searching: _searching,
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: _defaultZoom,
                          minZoom: 4,
                          maxZoom: 18,
                          onMapEvent: _onMapEvent,
                        ),
                        children: const [
                          _OsmTileLayer(),
                        ],
                      ),
                    ),
                  ),
                  const Center(child: _CenterPin()),
                  Positioned(
                    right: 28,
                    bottom: 12,
                    // Zoom (+/−) + "mening joylashuvim" — ikkalasi ustma-ust.
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MapZoomControls(controller: _mapController),
                        const SizedBox(height: 12),
                        _MyLocationButton(
                          isDark: isDark,
                          busy: _locating,
                          onTap: _goToCurrentLocation,
                        ),
                      ],
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _SuggestionList(
                        items: _suggestions,
                        isDark: isDark,
                        onTap: _pickSuggestion,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _AddressBanner(
                addressText: _addressText,
                resolving: _resolving,
                isDark: isDark,
                lat: _center.latitude,
                lng: _center.longitude,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: ListingCtaButton(
                label: tr(l, 'services.k3d.continue'),
                enabled: !_resolving,
                onTap: _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────

class _OsmTileLayer extends StatelessWidget {
  const _OsmTileLayer();
  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'uz.kadastr.kadastr',
      maxZoom: 19,
    );
  }
}

/// Map ustidagi "joriy joylashuv" tugmasi — geolocator orqali GPS oladi.
class _MyLocationButton extends StatelessWidget {
  const _MyLocationButton({
    required this.isDark,
    required this.busy,
    required this.onTap,
  });

  final bool isDark;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.splashGreen,
                  ),
                )
              : const Icon(
                  Icons.my_location,
                  color: AppColors.splashGreen,
                  size: 24,
                ),
        ),
      ),
    );
  }
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        // Anchor the pin's tip to the geographic center — the icon's pixel
        // midpoint sits below the tip, so push it up half its height.
        padding: const EdgeInsets.only(bottom: 44),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // A small, soft ground shadow right under the tip — anchors the pin
            // to the map without the ugly teardrop drop-shadow behind it.
            Positioned(
              bottom: 1,
              child: Container(
                width: 14,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 3,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ),
            const Icon(
              Icons.location_on,
              color: AppColors.splashGreen,
              size: 44,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.isDark,
    required this.searching,
  });

  final TextEditingController controller;
  final bool isDark;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final hint = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    return TextField(
      controller: controller,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      textInputAction: TextInputAction.search,
      style: TextStyle(fontFamily: 'MTSText', fontSize: 15, color: text),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintText: L.searchAddress(Localizations.localeOf(context)),
        hintStyle: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 15,
          color: hint,
        ),
        filled: true,
        fillColor: fill,
        prefixIcon: Icon(Icons.search, color: hint),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.splashGreen,
                  ),
                ),
              )
            : (controller.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, color: hint, size: 20),
                    onPressed: () => controller.clear(),
                  )),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.splashGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.items,
    required this.isDark,
    required this.onTap,
  });

  final List<GeoSuggestion> items;
  final bool isDark;
  final ValueChanged<GeoSuggestion> onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Material(
      color: bg,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length && i < 6; i++) ...[
            InkWell(
              onTap: () => onTap(items[i]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _iconFor(items[i].kind),
                      color: AppColors.splashGreen,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items[i].name,
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (items[i].description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              items[i].description,
                              style: TextStyle(
                                fontFamily: 'MTSText',
                                fontSize: 12,
                                color: sub,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1 && i < 5)
              Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }

  IconData _iconFor(String? kind) {
    switch (kind) {
      case 'metro':
      case 'railway_station':
        return Icons.train;
      case 'house':
      case 'street':
        return Icons.home_outlined;
      case 'biz':
        return Icons.business_outlined;
      case 'amenity':
        return Icons.location_city;
      default:
        return Icons.place_outlined;
    }
  }
}

class _AddressBanner extends StatelessWidget {
  const _AddressBanner({
    required this.addressText,
    required this.resolving,
    required this.isDark,
    required this.lat,
    required this.lng,
  });

  final String? addressText;
  final bool resolving;
  final bool isDark;
  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final text = isDark ? Colors.white : AppColors.textBlack;
    final sub = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.place_outlined,
            color: AppColors.splashGreen,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolving
                      ? tr(l, 'services.k3d.location.detecting_address')
                      : (addressText ??
                          tr(l, 'services.k3d.location.address_not_found')),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: text,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 11,
                    color: sub,
                  ),
                ),
              ],
            ),
          ),
          if (resolving)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.splashGreen,
              ),
            ),
        ],
      ),
    );
  }
}

