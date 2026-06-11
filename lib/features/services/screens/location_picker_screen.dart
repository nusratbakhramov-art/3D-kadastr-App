/// Xaritadan manzil tanlash uchun qayta ishlatiladigan ekran.
///
/// AI baholashdagi `ai_location_screen.dart` UX'ini takrorlaydi, lekin
/// AiBaholashBundle'ga bog'liq emas — tanlangan `AiLocationInfo` ni
/// `Navigator.pop` orqali qaytaradi. TZ wizardlarida manzil maydoni shu
/// ekranni ochadi.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../data/geocoder_client.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/map_zoom_controls.dart';
import '../widgets/service_app_bar.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial});

  /// Oldindan tanlangan manzil (mavjud bo'lsa, shu nuqtadan boshlaymiz).
  final AiLocationInfo? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _defaultCenter = LatLng(41.2995, 69.2401); // Toshkent
  static const _defaultZoom = 13.5;

  late final MapController _mapController;
  late final GeocoderClient _geocoder;
  final TextEditingController _searchCtrl = TextEditingController();

  late LatLng _center;

  List<GeoSuggestion> _suggestions = const [];
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _searching = false;
  bool _suppressSearch = false;

  String? _addressText;
  bool _resolving = false;
  Timer? _reverseDebounce;
  int _reverseRequestId = 0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _geocoder = GeocoderClient();
    final init = widget.initial;
    _center = init != null ? LatLng(init.lat, init.lng) : _defaultCenter;
    _addressText = init?.addressText;
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

  // ── Search ─────────────────────────────────────────────────────────────
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
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
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
      _addressText = s.description.isEmpty ? s.name : '${s.name}, ${s.description}';
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
    } catch (_) {
      if (!mounted || id != _reverseRequestId) return;
      setState(() => _resolving = false);
    }
  }

  void _confirm() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      AiLocationInfo(
        lat: _center.latitude,
        lng: _center.longitude,
        addressText: _addressText,
      ),
    );
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
                title: _PickerStrings.title(l),
                subtitle: _PickerStrings.subtitle(l),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SearchInput(
                controller: _searchCtrl,
                isDark: isDark,
                searching: _searching,
                locale: l,
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
                        children: const [_OsmTileLayer()],
                      ),
                    ),
                  ),
                  const Center(child: _CenterPin()),
                  Positioned(
                    right: 28,
                    bottom: 12,
                    child: MapZoomControls(controller: _mapController),
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
                locale: l,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: ListingCtaButton(
                label: _PickerStrings.confirmAddress(l),
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

// ── Sub-widgets (ai_location_screen UX bilan bir xil) ──────────────────
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

class _CenterPin extends StatelessWidget {
  const _CenterPin();
  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Padding(
        padding: EdgeInsets.only(bottom: 44),
        child: Icon(
          Icons.location_on,
          color: AppColors.splashGreen,
          size: 44,
          shadows: [
            Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
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
    required this.locale,
  });

  final TextEditingController controller;
  final bool isDark;
  final bool searching;
  final Locale locale;

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintText: _PickerStrings.searchHint(locale),
        hintStyle: TextStyle(fontFamily: 'MTSText', fontSize: 15, color: hint),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(_iconFor(items[i].kind),
                        color: AppColors.splashGreen, size: 22),
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
    required this.locale,
  });

  final String? addressText;
  final bool resolving;
  final bool isDark;
  final double lat;
  final double lng;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
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
          const Icon(Icons.place_outlined, color: AppColors.splashGreen, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolving
                      ? _PickerStrings.resolving(locale)
                      : (addressText ?? _PickerStrings.addressNotFound(locale)),
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

class _PickerStrings {
  const _PickerStrings._();

  static String title(Locale l) => switch (l.languageCode) {
        'ru' => 'Выберите адрес',
        'en' => 'Pick an address',
        _ => 'Manzilni tanlang',
      };

  static String subtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Перетащите пин в нужное место',
        'en' => 'Drag the pin to the desired spot',
        _ => 'Pinni kerakli joyga suring',
      };

  static String searchHint(Locale l) => switch (l.languageCode) {
        'ru' => 'Поиск адреса, улицы или объекта',
        'en' => 'Search address, street or place',
        _ => 'Manzil, ko\'cha yoki obyekt qidirish',
      };

  static String resolving(Locale l) => switch (l.languageCode) {
        'ru' => 'Определяется…',
        'en' => 'Resolving…',
        _ => 'Aniqlanmoqda…',
      };

  static String addressNotFound(Locale l) => switch (l.languageCode) {
        'ru' => 'Адрес не найден',
        'en' => 'Address not found',
        _ => 'Manzil topilmadi',
      };

  static String confirmAddress(Locale l) => switch (l.languageCode) {
        'ru' => 'Подтвердить адрес',
        'en' => 'Confirm address',
        _ => 'Manzilni tasdiqlash',
      };
}
