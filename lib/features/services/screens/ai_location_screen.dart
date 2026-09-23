/// Step 3 of AI Baholash — pick the property's location on a map.
///
/// UX (per spec):
///   - Pin always at the **map center**. As the user pans, lat/lng updates.
///   - Search input above the map: typing → autocomplete dropdown → tap → map flies there.
///   - When the map stops moving (or autocomplete selection lands), we
///     reverse-geocode and show "Manzil shumi?" with the address text +
///     Confirm button. If wrong, user keeps moving the pin.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/i18n.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../ai_draft_saver.dart';
import '../data/geocoder_client.dart';
import '../models/ai_baholash_bundle.dart';
import '../models/ai_wizard_steps.dart';
import '../widgets/map_zoom_controls.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/wizard_nav_bar.dart';
import 'ai_purpose_screen.dart';

class AiLocationScreen extends StatefulWidget {
  const AiLocationScreen({super.key, required this.bundle});

  final AiBaholashBundle bundle;

  @override
  State<AiLocationScreen> createState() => _AiLocationScreenState();
}

class _AiLocationScreenState extends State<AiLocationScreen> {
  // Toshkent markazi — sensible default starting point for UZ.
  static const _defaultCenter = LatLng(41.2995, 69.2401);
  static const _defaultZoom = 13.5;

  late final MapController _mapController;
  late final GeocoderClient _geocoder;
  final TextEditingController _searchCtrl = TextEditingController();

  LatLng _center = _defaultCenter;

  // Search state.
  List<GeoSuggestion> _suggestions = const [];
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _searching = false;
  // True while we programmatically set the search text from a tapped
  // suggestion — stops the controller listener from re-running the search and
  // reopening the dropdown (which otherwise forced a second tap).
  bool _suppressSearch = false;

  // Reverse-geocode state.
  String? _addressText;
  bool _resolving = false;
  Timer? _reverseDebounce;
  int _reverseRequestId = 0;

  // Current-location (geolocator) state.
  bool _locating = false;

  /// Pin hozir QAYERDAN kelgan.
  ///
  /// ⚠️ NEGA KERAK. Ilgari "haqiqiy joy tanlandimi" degan savolga
  /// `_addressText != null || _center != _defaultCenter` javob berardi. Kadastr
  /// manzili geokodlanmasa pin Toshkent markazida qolar, reverse-geokod esa
  /// o'sha markazning manzil matnini qo'yar edi — shart bajarilib, TEGILMAGAN
  /// sukut nuqtasi obyektning joylashuvi sifatida saqlanardi. Matn emas,
  /// nuqtaning KELIB CHIQISHI hal qilishi kerak.
  _PinSource _pinSource = _PinSource.none;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _geocoder = GeocoderClient();
    _searchCtrl.addListener(_onSearchChanged);
    // If a location was already chosen (resume from draft, or the user went
    // back and returned to this step), restore that exact pin — don't re-geocode
    // from the cadastre address, which would silently overwrite their choice.
    final saved = widget.bundle.location;
    if (saved != null && (saved.lat != 0 || saved.lng != 0)) {
      _center = LatLng(saved.lat, saved.lng);
      _addressText = saved.addressText;
      _pinSource = _PinSource.saved;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(_center, 16);
        } catch (_) {
          // Map not attached yet — the next build picks up _center.
        }
        // No confirmed address text saved — reverse-geocode the restored pin.
        if (_addressText == null) _scheduleReverse();
      });
      return;
    }
    // First visit, and the user already picked the parcel on the geoportal map
    // (step 1): use THAT centre. It is the registry polygon's own centre, so it
    // beats any geocode of the address text — and it means the user is not made
    // to mark the same property on a map twice.
    //
    // ⚠️ Bu QURILMANING GPS'i EMAS. GPS faqat «mening joylashuvim» tugmasi
    // bosilganda ishlaydi va hech qachon obyektning joylashuvi sifatida
    // saqlanmaydi.
    final parcel = widget.bundle.parcelCenter;
    if (parcel != null && (parcel.lat != 0 || parcel.lng != 0)) {
      _center = LatLng(parcel.lat, parcel.lng);
      _pinSource = _PinSource.parcel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(_center, 17);
        } catch (_) {
          // Map not attached yet — the next build picks up _center.
        }
        _scheduleReverse();
      });
      return;
    }
    // No parcel picked (the number was typed by hand): auto-place the pin at
    // the property's real location (geocoded from the davreestr cadastre
    // address) once the map is laid out. Otherwise the user is left on the
    // Tashkent default and can submit the wrong spot — which pulls comps from
    // the wrong area and badly skews the valuation.
    // Deferred to post-frame so the MapController is attached before we move it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initFromCadastreAddress();
    });
  }

  @override
  void dispose() {
    // Orqaga qaytishда ham fon rejimida saqlash — tanlangan joy yo'qolmasin.
    if (_hasResolvedLocation) {
      _captureToBundle();
      saveAiDraftStepInBackground(widget.bundle, 'location');
    }
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    _geocoder.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ── Initial location (auto-locate from cadastre address) ─────────────

  /// Geocode the davreestr cadastre address and drop the pin there, so the
  /// valuation uses comps from the property's real area instead of the Tashkent
  /// default. davreestr addresses are very specific (…-uy, Korpus, -xonadon)
  /// and often miss an exact geocode, so we try the full address then coarser
  /// variants (region → tuman → MFY). Falls back to the default center + a
  /// reverse-geocode if nothing resolves.
  Future<void> _initFromCadastreAddress() async {
    final address = widget.bundle.kadastr.address?.trim() ?? '';
    if (address.isEmpty) {
      _scheduleReverse();
      return;
    }
    setState(() => _resolving = true);
    for (final q in _addressQueries(address)) {
      try {
        final results = await _geocoder.autocomplete(q);
        if (!mounted) return;
        if (results.isNotEmpty) {
          final s = results.first;
          setState(() {
            _center = LatLng(s.lat, s.lng);
            // Keep the authoritative davreestr address as the confirmed text.
            _addressText = address;
            _pinSource = _PinSource.cadastreAddress;
            _resolving = false;
          });
          try {
            _mapController.move(_center, 16);
          } catch (_) {
            // Map not attached yet — the next build picks up _center.
          }
          return;
        }
      } catch (_) {
        // Try the next, coarser variant.
      }
    }
    // No geocode hit — fall back to the default center + reverse-geocode.
    if (!mounted) return;
    setState(() => _resolving = false);
    _scheduleReverse();
  }

  /// Full address first, then coarser fallbacks: drop the most specific
  /// trailing segments (house / korpus / apartment), keeping region → MFY so a
  /// miss on the exact house still lands us in the right district.
  List<String> _addressQueries(String address) {
    final queries = <String>[address];
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length > 3) queries.add(parts.take(3).join(', '));
    if (parts.length > 2) queries.add(parts.take(2).join(', '));
    return queries;
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
    // Cancel any pending/in-flight autocomplete so a late response can't
    // repopulate the dropdown after we've made a selection.
    _searchDebounce?.cancel();
    _searchRequestId++;
    // Set the text WITHOUT retriggering the search listener, and place the
    // caret at the end (avoids the iOS select-all / replace-suggestion glitch
    // that the bare `.text =` setter caused).
    _suppressSearch = true;
    _searchCtrl.value = TextEditingValue(
      text: s.name,
      selection: TextSelection.collapsed(offset: s.name.length),
    );
    _suppressSearch = false;
    setState(() {
      _suggestions = const [];
      _center = LatLng(s.lat, s.lng);
      _pinSource = _PinSource.search;
      _addressText = s.description.isEmpty
          ? s.name
          : '${s.name}, ${s.description}';
    });
    _mapController.move(_center, 17);
    // Even though we already have the description text, run reverse so the
    // confirmed text matches what the map center actually resolves to.
    _scheduleReverse();
  }

  // ── Reverse geocoding ────────────────────────────────────────────────

  void _onMapEvent(MapEvent event) {
    // We care about *settled* positions, not every frame of a drag. The
    // debounce in _scheduleReverse handles that.
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd ||
        event is MapEventScrollWheelZoom) {
      final c = _mapController.camera.center;
      if (c.latitude == _center.latitude && c.longitude == _center.longitude) {
        return;
      }
      setState(() {
        _center = c;
        _pinSource = _PinSource.userPan;
      });
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
      // Don't toast — failed reverse just leaves the address blank, user
      // can still confirm with raw coords.
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
        if (mounted) AppToast.error(context, _AiLocationStrings.locationOff(l));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          AppToast.error(context, _AiLocationStrings.locationDenied(l));
        }
        return;
      }
      setState(() => _locating = true);
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      // Foydalanuvchi TUGMANI o'zi bosdi — bu ongli tanlov, shuning uchun pin
      // shu yerga ko'chadi. Avtomatik ravishda HECH QACHON bunday bo'lmaydi.
      setState(() {
        _center = here;
        _pinSource = _PinSource.userPan;
        _locating = false;
      });
      _mapController.move(here, 17);
      _scheduleReverse();
    } catch (_) {
      if (!mounted) return;
      setState(() => _locating = false);
      AppToast.error(context, _AiLocationStrings.locationError(l));
    }
  }

  // ── Confirm / submit ─────────────────────────────────────────────────

  Future<void> _confirm() async {
    HapticFeedback.lightImpact();
    _captureToBundle();
    // Fon rejimida saqlash — sekin backend navigatsiyani muzlatmasin.
    saveAiDraftStepInBackground(widget.bundle, 'purpose');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/purpose'),
        builder: (_) => AiPurposeScreen(bundle: widget.bundle),
      ),
    );
  }

  /// Joriy tanlangan joyni bundle'ga yozadi (oldinga ham, Orqaga ham).
  ///
  /// Nuqta bilan birga uning MANBAI ham yoziladi. Bu ekranga kelingan ekan,
  /// foydalanuvchi pinni o'zi tasdiqlaydi — shu sababli manba
  /// [AiLocationSource.manualMap]. Yagona istisno: pin uchastka markazidan
  /// kelgan va foydalanuvchi unga TEGMAGAN bo'lsa, manba `parcel` bo'lib
  /// qoladi (aniqroq va ishonchliroq belgi).
  void _captureToBundle() {
    widget.bundle.location = AiLocationInfo(
      lat: _center.latitude,
      lng: _center.longitude,
      addressText: _addressText,
    );
    widget.bundle.locationSource = switch (_pinSource) {
      _PinSource.none => AiLocationSource.none,
      _PinSource.parcel => AiLocationSource.parcel,
      _ => AiLocationSource.manualMap,
    };
  }

  /// Haqiqiy joy aniqlanganmi — Toshkent default'ini draftga yozmaslik uchun.
  bool get _hasResolvedLocation => _pinSource != _PinSource.none;

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
                title: _AiLocationStrings.appBarTitle(l),
                subtitle: _AiLocationStrings.appBarSubtitle(l),
                // Bu tugma butun oqimni yopadi — bitta qadam
                // orqaga EMAS. Qadamma-qadam qaytish pastda.
                onBack: () => confirmCloseAiWizard(context),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StepProgressBar(
                count: widget.bundle.aiStepCount,
                activeIndex: widget.bundle.aiStepIndex(AiStep.location),
              ),
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
                        children: [
                          _ModernTileLayer(isDark: isDark),
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
                locale: l,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: WizardNavBar(
                onBack: () => Navigator.of(context).maybePop(),
                onContinue: _confirm,
                continueLabel: _AiLocationStrings.confirm(l),
                continueEnabled: !_resolving,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────

class _ModernTileLayer extends StatelessWidget {
  const _ModernTileLayer({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Zamonaviy CartoDB basemap (bepul, API key shart emas). Qorong'i temada
    // Dark Matter, yorug'da Voyager — eski OSM raster o'rniga ancha toza/zamonaviy.
    final style = isDark ? 'dark_all' : 'voyager';
    return TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/rastertiles/$style/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
      userAgentPackageName: 'uz.kadastr.kadastr',
      maxZoom: 20,
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
        // Visually anchor the pin's tip to the geographic center — Icon's
        // pixel midpoint sits below the tip, so push it up half its height.
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintText: L.searchAddress(Localizations.localeOf(context)),
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
          borderSide: const BorderSide(
            color: AppColors.splashGreen,
            width: 1.4,
          ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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
                      ? _AiLocationStrings.detecting(locale)
                      : (addressText ?? _AiLocationStrings.notFound(locale)),
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

/// Xaritadagi pin qayerdan kelgani — [_AiLocationScreenState._pinSource].
enum _PinSource {
  /// Hech narsa tanlanmagan: pin hali ham Toshkent sukuti.
  none,

  /// Qoralamadan tiklangan (foydalanuvchi ilgari tasdiqlagan).
  saved,

  /// Geoportalda tanlangan uchastkaning markazi.
  parcel,

  /// Kadastr manzili matnidan geokodlangan.
  cadastreAddress,

  /// Qidiruv taklifidan tanlangan.
  search,

  /// Foydalanuvchi xaritani o'zi surgan (yoki «mening joylashuvim» bosgan).
  userPan,
}

class _AiLocationStrings {
  const _AiLocationStrings._();

  static String appBarTitle(Locale l) =>
      tr(l, 'services.ai.location.app_bar_title');

  static String appBarSubtitle(Locale l) =>
      tr(l, 'services.ai.location.app_bar_subtitle');

  static String confirm(Locale l) => tr(l, 'services.ai.location.confirm');

  static String detecting(Locale l) => tr(l, 'services.ai.location.detecting');

  static String notFound(Locale l) => tr(l, 'services.ai.location.not_found');

  static String locationOff(Locale l) =>
      tr(l, 'services.ai.location.location_off');

  static String locationDenied(Locale l) =>
      tr(l, 'services.ai.location.location_denied');

  static String locationError(Locale l) =>
      tr(l, 'services.ai.location.location_error');
}
