/// Xaritadan uy (kadastr uchastkasi) tanlash ekrani.
///
/// Oqim: xaritani surib uyni topadi → uy chegarasi ichiga bosadi → uchastka
/// QURILMADA topiladi (chegaralar allaqachon yuklangan) → bittadan ko'p bo'lsa
/// tanlash varag'i chiqadi → pastdagi kartochkada raqam ko'rinadi →
/// "Tanlash" bosilsa [NgisParcel] qaytariladi.
///
/// Bosish odatda tarmoqqa chiqmaydi. Tarmoq faqat ikki holatda kerak bo'ladi:
/// chegaralar hali yuklanmagan bo'lsa va uzoq masshtabda bosilgan bo'lsa —
/// shunda [NgisParcelClient.identifyAt] ga tushiladi.
///
/// Ekran KADASTR RAQAMINI qaytaradi, manzilni emas: geoportalning ochiq
/// qatlamida ko'cha manzili yo'q (sabab — [NgisParcelClient] izohida). Manzil
/// va maydonni chaqiruvchi ekran o'zining davreestr qidiruvi bilan to'ldiradi.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../data/ngis_parcel_client.dart';
import '../widgets/map_zoom_controls.dart';
import '../widgets/parcel_basemap.dart';
import '../widgets/parcel_choice_sheet.dart';
import '../widgets/parcel_map.dart';
import '../widgets/service_app_bar.dart';

class ParcelPickerScreen extends StatefulWidget {
  const ParcelPickerScreen({
    super.key,
    this.initialCenter,
    this.initialSelection,
  });

  /// Xarita shu nuqtadan ochiladi (avval tanlangan uchastka markazi yoki
  /// foydalanuvchining joylashuvi).
  final LatLng? initialCenter;

  /// Avval tanlangan uchastka — qayta ochilganda ajratib ko'rsatiladi.
  final NgisParcel? initialSelection;

  @override
  State<ParcelPickerScreen> createState() => _ParcelPickerScreenState();
}

class _ParcelPickerScreenState extends State<ParcelPickerScreen> {
  final MapController _map = MapController();
  final NgisParcelClient _client = NgisParcelClient();

  NgisParcel? _selected;
  bool _busy = false;
  bool _locating = false;
  ParcelBasemap _basemap = ParcelBasemap.satellite;

  /// Foydalanuvchining joriy joylashuvi — xaritadagi ko'k nuqta.
  Position? _me;
  StreamSubscription<Position>? _meSub;

  /// Qidiruvlar ketma-ketligi — foydalanuvchi tez-tez bossa, faqat oxirgi
  /// javob qabul qilinadi (eskisi kechikib kelib tanlovni almashtirmasin).
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _primeLocation();
  }

  /// Ekran ochilishida joylashuvni RUXSAT SO'RAMASDAN tiklaydi.
  ///
  /// `checkPermission` va `getLastKnownPosition` dialog chiqarmaydi va tarmoqqa
  /// chiqmaydi. Ruxsat allaqachon berilgan bo'lsa: ko'k nuqta darhol paydo
  /// bo'ladi va (uchastka oldindan tanlanmagan bo'lsa) xarita o'sha joyga
  /// sakraydi — foydalanuvchi Toshkent umumiy ko'rinishidan o'z mahallasigacha
  /// qo'lda yaqinlashtirib o'tirmaydi. Ruxsat yo'q bo'lsa hech narsa
  /// o'zgarmaydi: dialogni faqat "mening joylashuvim" tugmasi chiqaradi.
  Future<void> _primeLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (!_granted(permission) || !mounted) return;

      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() => _me = pos);
        if (widget.initialCenter == null) _moveWhenReady(pos);
      }
      _watchLocation();
    } catch (_) {
      // Xizmat o'chiq yoki platforma rad etdi — nuqta shunchaki ko'rinmaydi.
    }
  }

  static bool _granted(LocationPermission p) =>
      p == LocationPermission.always || p == LocationPermission.whileInUse;

  /// Joylashuvni kuzatishni boshlaydi — ko'k nuqta foydalanuvchi bilan birga
  /// suriladi.
  ///
  /// `distanceFilter` ATAYLAB 5 metr: uchastka tanlashda undan mayda siljish
  /// hech narsani o'zgartirmaydi, har bir o'lchov esa batareyani yeydi.
  void _watchLocation() {
    if (_meSub != null) return;
    _meSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (pos) {
        if (mounted) setState(() => _me = pos);
      },
      // Oqim uzilsa nuqta oxirgi ma'lum joyda qoladi — ekran ishlayveradi.
      onError: (_) {},
      cancelOnError: true,
    );
  }

  /// Xaritani [pos] ga olib boradi. Kontroller xarita qurilgandan keyin
  /// ulanadi, shuning uchun siljish kadr oxiriga qoldiriladi.
  void _moveWhenReady(Position pos) {
    final target = LatLng(pos.latitude, pos.longitude);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.move(target, 17.5);
      } catch (_) {
        // Xarita hali ulanmagan — boshlang'ich ko'rinish qoladi.
      }
    });
  }

  @override
  void dispose() {
    _meSub?.cancel();
    _client.dispose();
    super.dispose();
  }

  /// Xaritada bosilganda: [hits] — xaritaning o'zi topgan uchastkalar.
  ///
  /// Odatda javob shu yerda tugaydi va foydalanuvchi kutmaydi. Ro'yxat bo'sh
  /// bo'lsagina tarmoqqa chiqiladi — chegaralar chizilmaydigan masshtabda
  /// bosish ham ishlashi uchun.
  Future<void> _onMapTap(LatLng point, List<NgisParcel> hits) async {
    HapticFeedback.selectionClick();
    if (hits.isNotEmpty) {
      await _choose(hits);
      return;
    }
    await _identify(point);
  }

  Future<void> _identify(LatLng point) async {
    final l = Localizations.localeOf(context);
    final reqId = ++_requestId;
    setState(() => _busy = true);

    List<NgisParcel> found;
    try {
      found = await _client.identifyAt(point);
    } on NgisException catch (e) {
      if (!mounted || reqId != _requestId) return;
      setState(() => _busy = false);
      AppToast.error(context, '${tr(l, 'services.ai.parcel.failed')}: ${e.message}');
      return;
    }
    if (!mounted || reqId != _requestId) return;
    setState(() => _busy = false);

    if (found.isEmpty) {
      AppToast.error(context, tr(l, 'services.ai.parcel.not_found'));
      return;
    }
    await _choose(found);
  }

  Future<void> _choose(List<NgisParcel> found) async {
    if (found.length == 1) {
      _select(found.first);
      return;
    }
    final chosen = await showParcelChoiceSheet(context, parcels: found);
    if (chosen != null && mounted) _select(chosen);
  }

  void _select(NgisParcel parcel) {
    HapticFeedback.lightImpact();
    setState(() => _selected = parcel);
    _fillPlace(parcel);
  }

  /// Joylashuv nomlarini fonda to'ldiradi.
  ///
  /// Ko'rinish so'rovi tez bo'lishi uchun xatlovsiz qatlamdan faqat viloyat va
  /// tuman keladi, ba'zi yozuvlarda esa ular umuman bo'sh. Kartochkada
  /// "shu joymi?" degan savolga javob bo'lishi uchun to'liq yozuv keyinroq
  /// olinadi — tanlash esa shu paytgacha ham ishlayveradi.
  Future<void> _fillPlace(NgisParcel parcel) async {
    if (parcel.placeLabel.isNotEmpty) return;
    final full = await _client.details(parcel);
    if (full == null || !mounted) return;
    if (_selected != parcel) return;
    setState(() => _selected = parcel.mergePlace(full));
  }

  void _confirm() {
    final parcel = _selected;
    if (parcel == null) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(parcel);
  }

  /// Joriy joylashuvga o'tadi. Uchastka O'ZIDAN-O'ZI tanlanmaydi: GPS aniqligi
  /// 10-20 metr bo'lishi mumkin va qo'shni hovlini tanlab qo'yish — baholash
  /// arizasi uchun jimgina yuz beradigan xato bo'lardi.
  Future<void> _locateMe() async {
    if (_locating) return;
    final l = Localizations.localeOf(context);
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          AppToast.error(
            context,
            tr(l, 'services.location.map.location_disabled'),
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          AppToast.error(
            context,
            tr(l, 'services.location.map.permission_denied'),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() => _me = pos);
      _watchLocation();
      _map.move(LatLng(pos.latitude, pos.longitude), 18);
    } catch (e) {
      if (mounted) {
        AppToast.error(context, '${tr(l, 'services.location.map.locate_failed')}: $e');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final me = _me;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: ServiceAppBar(
                title: tr(l, 'services.ai.parcel.title'),
                subtitle: tr(l, 'services.ai.parcel.subtitle'),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ParcelMap(
                          controller: _map,
                          client: _client,
                          basemap: _basemap,
                          initialCenter: widget.initialCenter,
                          initialZoom:
                              widget.initialCenter == null ? 13 : 18,
                          selected: _selected,
                          myLocation: me == null
                              ? null
                              : LatLng(me.latitude, me.longitude),
                          myLocationAccuracy: me?.accuracy,
                          busy: _busy,
                          onTap: _onMapTap,
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Column(
                          children: [
                            MapZoomControls(controller: _map, maxZoom: 20),
                            const SizedBox(height: 8),
                            _BasemapToggle(
                              basemap: _basemap,
                              onTap: () => setState(
                                () => _basemap = _basemap.other,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _LocateFab(busy: _locating, onTap: _locateMe),
                      ),
                      Positioned(
                        left: 12,
                        right: 76,
                        bottom: 12,
                        child: _SelectionBadge(
                          parcel: _selected,
                          isDark: isDark,
                          locale: l,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ListingCtaButton(
                label: _selected == null
                    ? tr(l, 'services.ai.parcel.tap_first')
                    : tr(l, 'services.ai.parcel.use'),
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

/// Tanlangan uchastka (yoki yo'riqnoma) — xarita ustidagi kartochka.
class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({
    required this.parcel,
    required this.isDark,
    required this.locale,
  });

  final NgisParcel? parcel;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? Colors.black.withValues(alpha: 0.66)
        : Colors.white.withValues(alpha: 0.94);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF6C7378);
    final p = parcel;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: p == null
          ? Text(
              tr(locale, 'services.ai.parcel.hint'),
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 12.5,
                height: 1.35,
                color: subColor,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.cadastreNumber,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
                if (p.placeLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.placeLabel,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 12,
                      height: 1.3,
                      color: subColor,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Sun'iy yo'ldosh ↔ sxema almashtirgichi.
///
/// Geoportaldagi "Sputnik / Sxema" tanlovining ixchamlashtirilgani. Sun'iy
/// yo'ldosh sukut bo'yicha: foydalanuvchi o'z tomini taniydi. Sxema esa
/// ko'chalar nomi kerak bo'lganda asqotadi.
class _BasemapToggle extends StatelessWidget {
  const _BasemapToggle({required this.basemap, required this.onTap});

  final ParcelBasemap basemap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final satellite = basemap.kind == ParcelBasemapKind.satellite;
    return Material(
      color: isDark ? const Color(0xFF1F2426) : Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            satellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
            size: 21,
            color: isDark ? Colors.white : AppColors.textBlack,
          ),
        ),
      ),
    );
  }
}

class _LocateFab extends StatelessWidget {
  const _LocateFab({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1F2426) : Colors.white,
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
                : const Icon(
                    Icons.my_location,
                    color: AppColors.splashGreen,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}
