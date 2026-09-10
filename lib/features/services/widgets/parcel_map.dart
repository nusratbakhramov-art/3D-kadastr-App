/// Kadastr uchastkalari xaritasi — sun'iy yo'ldosh asosi + geoportal
/// chegaralari.
///
/// Chegaralar VEKTOR bo'lib keladi va qurilmada chiziladi (sabab —
/// [NgisParcelClient] izohida). Amaliy natijasi:
/// - surish va masshtablashda chizma darhol qayta chiziladi, kutish yo'q;
/// - bosilgan uy qurilmaning o'zida topiladi — kadastr raqami bir zumda;
/// - ko'rinish bir marta yuklangach, atrofda yurish yana so'rov tug'dirmaydi.
///
/// Yangi so'rov faqat ikki holatda ketadi: ko'rinish oldin yuklangan
/// maydondan chiqib ketsa, yoki masshtab qatlam chegarasidan o'tsa.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/i18n/app_translations.dart';
import '../data/ngis_parcel_client.dart';
import 'parcel_basemap.dart';

/// Toshkent markazi — joylashuv ma'lum bo'lmaganda boshlang'ich ko'rinish.
const LatLng kParcelMapFallbackCenter = LatLng(41.311081, 69.240562);

/// Uy chegaralari shu zoomdan boshlab chiziladi.
///
/// Qiymat qatlamlarning o'z chegarasidan olinadi — geoportalda ham aynan shu
/// masshtabda paydo bo'ladi.
final double kParcelHousesZoom = kNgisParcelLayers
    .where((l) => l.id == 'turar' || l.id == 'xatlovsiz')
    .map((l) => l.minZoom)
    .reduce((a, b) => a < b ? a : b);

/// Kadastr raqamlari uchastka ustida shu zoomdan boshlab yoziladi.
const double kParcelLabelZoom = 17.5;

class ParcelMap extends StatefulWidget {
  const ParcelMap({
    super.key,
    required this.onTap,
    this.client,
    this.controller,
    this.initialCenter,
    this.initialZoom = 17.5,
    this.selected,
    this.basemap = ParcelBasemap.satellite,
    this.myLocation,
    this.myLocationAccuracy,
    this.interactive = true,
    this.busy = false,
  });

  /// Xaritada bosilgan nuqta va o'sha nuqtadagi uchastkalar — ustidagisidan
  /// boshlab. Ro'yxat bo'sh bo'lsa chaqiruvchi tarmoqdan so'rab ko'rishi mumkin
  /// ([NgisParcelClient.identifyAt]).
  final void Function(LatLng point, List<NgisParcel> hits) onTap;

  /// Tashqaridan berilgan klient — ekran bilan bitta ulanishni bo'lishish
  /// uchun. Berilmasa vidjet o'zi yaratadi va o'zi yopadi.
  final NgisParcelClient? client;

  final MapController? controller;
  final LatLng? initialCenter;
  final double initialZoom;

  /// Tanlangan uchastka — chegarasi yashil bilan ajratiladi.
  final NgisParcel? selected;

  final ParcelBasemap basemap;

  /// Foydalanuvchining joriy joylashuvi — ko'k nuqta bilan ko'rsatiladi.
  ///
  /// `null` bo'lsa hech narsa chizilmaydi: joylashuv hali ma'lum emas yoki
  /// ruxsat berilmagan.
  final LatLng? myLocation;

  /// Joylashuv aniqligi, metrda — nuqta atrofidagi doira radiusi.
  ///
  /// Doira ATAYLAB chiziladi: shahar ichida GPS 10-30 metr xato qilishi
  /// odatiy hol va foydalanuvchi ko'k nuqtani "aynan mening uyim" deb
  /// tushunmasligi kerak — u qo'shni hovlida turgan bo'lishi mumkin.
  final double? myLocationAccuracy;

  /// `false` — surish/masshtablash o'chiriladi (ro'yxat ichidagi ko'rinish
  /// uchun: aks holda xarita ro'yxatning vertikal siljishini o'g'irlaydi).
  final bool interactive;

  /// Chaqiruvchi tomonidagi ish ketayotganini ko'rsatadi.
  final bool busy;

  @override
  State<ParcelMap> createState() => _ParcelMapState();
}

class _ParcelMapState extends State<ParcelMap> {
  late final MapController _map = widget.controller ?? MapController();
  late final NgisParcelClient _client = widget.client ?? NgisParcelClient();
  bool get _ownsClient => widget.client == null;

  final LayerHitNotifier<NgisParcel> _hits = ValueNotifier(null);

  /// Tile provayderi bir marta yaratiladi: `build` har bir yuklash bosqichida
  /// qayta chaqiriladi, provayderni har safar yangilash esa keshga
  /// tegmasa ham ortiqcha obyekt yaratardi.
  final CachedTileProvider _tiles = CachedTileProvider();

  /// Qatlam id → yuklangan maydon va undagi uchastkalar.
  final Map<String, _LayerShot> _shots = {};

  Timer? _debounce;
  bool _ready = false;
  int _generation = 0;
  int _pending = 0;

  /// Oxirgi ma'lum zoom — chizishda ishlatiladi.
  double _zoom = 0;

  /// Kadastr raqamlari yozilyaptimi. Alohida saqlanadi, chunki qayta chizish
  /// AYNAN shu chegara kesib o'tilganda kerak: har bir zoom kadrida
  /// poligonlarni qaytadan yig'ish behuda ish bo'lardi.
  bool _labels = false;

  /// Uy chegaralari chizilyaptimi. Chizilmasa foydalanuvchiga nima qilish
  /// kerakligi aytiladi — aks holda u bo'm-bo'sh xaritaga bosib, "topilmadi"
  /// javobini olaverardi.
  bool _detailed = false;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
    _labels = _zoom >= kParcelLabelZoom;
    _detailed = _zoom >= kParcelHousesZoom;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hits.dispose();
    if (_ownsClient) _client.dispose();
    super.dispose();
  }

  /// Kamera to'xtaganidan keyin yuklashni rejalashtiradi.
  ///
  /// Har qanday xarita hodisasiga bog'lanadi: surish davomida taymer qayta
  /// tiklanadi, shuning uchun so'rov faqat barmoq uzilgach ketadi. Dasturiy
  /// siljish (`controller.move`) ham shu yo'l bilan qamrab olinadi — u
  /// `MoveEnd` chiqarmaydi.
  void _schedule([Duration delay = const Duration(milliseconds: 180)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, _load);
  }

  Future<void> _load() async {
    if (!mounted || !_ready) return;

    final camera = _map.camera;
    final visible = camera.visibleBounds;
    final zoom = camera.zoom;
    final generation = ++_generation;
    var dropped = false;

    for (final layer in kNgisParcelLayers) {
      // Masshtabdan chiqqan qatlam DARHOL o'chadi: uzoqdan minglab poligon
      // chizish ham ma'nosiz, ham sekin.
      if (zoom < layer.minZoom) {
        if (_shots.remove(layer.id) != null) dropped = true;
        continue;
      }
      if (_shots[layer.id]?.covers(visible) ?? false) continue;
      unawaited(_fetch(layer, visible, generation));
    }

    if (dropped && mounted) setState(() {});
  }

  Future<void> _fetch(
    NgisLayer layer,
    LatLngBounds visible,
    int generation,
  ) async {
    // Ko'rinishdan kengroq maydon so'raladi — kichik surishlar yangi so'rov
    // tug'dirmasin.
    final area = _pad(visible, 0.45);
    setState(() => _pending++);
    final List<NgisParcel> parcels;
    try {
      parcels = await _client.parcelsInBounds(layer, area);
    } catch (_) {
      // Bitta qatlamning yiqilishi qolganini to'xtatmaydi — eskisi ekranda
      // qoladi, foydalanuvchi uchun bu hech qanday natijadan yaxshi.
      if (mounted) setState(() => _pending--);
      return;
    }
    if (!mounted) return;
    setState(() {
      _pending--;
      // Kech kelgan javob yangi ko'rinish ustiga yozilmasin.
      if (generation == _generation) {
        _shots[layer.id] = _LayerShot(bounds: area, parcels: parcels);
      }
    });
  }

  /// Chizishga arziydigan aniqlik radiusi, aks holda `null`.
  ///
  /// Chegara 300 m: undan yomon aniqlik odatda uyali tarmoq bo'yicha
  /// taxmin degani va doira butun ko'rinishni bo'yab tashlaydi.
  static double? _usableAccuracy(double? value) {
    if (value == null || !value.isFinite || value <= 0 || value > 300) {
      return null;
    }
    return value;
  }

  /// Chegaralarni har tomonga [factor] ulush kengaytiradi.
  static LatLngBounds _pad(LatLngBounds b, double factor) {
    final dLat = (b.north - b.south) * factor;
    final dLng = (b.east - b.west) * factor;
    return LatLngBounds(
      LatLng((b.south - dLat).clamp(-85.0, 85.0), b.west - dLng),
      LatLng((b.north + dLat).clamp(-85.0, 85.0), b.east + dLng),
    );
  }

  void _onTap(LatLng point) {
    // `hitNotifier` bosish dispetcherlanishidan OLDIN, hit-test paytida
    // to'ldiriladi — shuning uchun bu yerda o'qish to'g'ri.
    final hit = _hits.value;
    final unique = LinkedHashSet<NgisParcel>.from(hit?.hitValues ?? const []);
    widget.onTap(point, unique.toList(growable: false));
  }

  List<Polygon<NgisParcel>> _polygons() {
    final selected = widget.selected;
    final labels = _labels;
    final out = <Polygon<NgisParcel>>[];

    // `kNgisParcelLayers` ustma-ust chizilish tartibida: oxirgisi eng ustida,
    // ya'ni bosilganda birinchi bo'lib qaytadi.
    for (final layer in kNgisParcelLayers) {
      final shot = _shots[layer.id];
      if (shot == null) continue;
      for (final parcel in shot.parcels) {
        if (parcel == selected) continue; // tanlangani eng oxirida chiziladi
        for (var i = 0; i < parcel.parts.length; i++) {
          out.add(
            Polygon(
              points: parcel.parts[i],
              color: layer.fill,
              borderColor: layer.stroke,
              borderStrokeWidth: 1.2,
              hitValue: parcel,
              // Yozuv faqat bitta bo'lakka — aks holda bo'lingan uchastkada
              // raqam ikki marta chiqadi.
              label: labels && i == 0 ? parcel.cadastreNumber : null,
              labelPlacement: PolygonLabelPlacement.centroid,
              labelStyle: const TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1.1,
                color: Color(0xFF1A1A1A),
                shadows: [
                  Shadow(color: Color(0xCCFFFFFF), blurRadius: 3),
                  Shadow(color: Color(0xCCFFFFFF), blurRadius: 6),
                ],
              ),
            ),
          );
        }
      }
    }

    if (selected != null) {
      for (final part in selected.parts) {
        out.add(
          Polygon(
            points: part,
            color: const Color(0x4D00C853),
            borderColor: const Color(0xFF00E676),
            borderStrokeWidth: 3,
            hitValue: selected,
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final polygons = _polygons();
    final busy = widget.busy || _pending > 0;
    final basemap = widget.basemap;
    final me = widget.myLocation;
    // Juda past aniqlikda doira butun mahallani qoplaydi va faqat xalaqit
    // beradi — bunday holatda nuqtaning o'zi qoladi.
    final accuracy = _usableAccuracy(widget.myLocationAccuracy);

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: widget.initialCenter ?? kParcelMapFallbackCenter,
              initialZoom: widget.initialZoom,
              minZoom: 4,
              maxZoom: 20,
              interactionOptions: InteractionOptions(
                flags: widget.interactive
                    ? InteractiveFlag.all & ~InteractiveFlag.rotate
                    : InteractiveFlag.none,
              ),
              onTap: (_, point) => _onTap(point),
              onMapReady: () {
                _ready = true;
                _zoom = _map.camera.zoom;
                // Kadr ichida `setState` chaqirilmasin — yuklash keyingi
                // navbatga qoldiriladi.
                _schedule(Duration.zero);
              },
              onMapEvent: (event) {
                _zoom = event.camera.zoom;
                final labels = _zoom >= kParcelLabelZoom;
                final detailed = _zoom >= kParcelHousesZoom;
                if (labels != _labels || detailed != _detailed) {
                  _labels = labels;
                  _detailed = detailed;
                  // Hodisa layout paytida ham kelishi mumkin — qayta chizish
                  // kadr oxiriga qoldiriladi.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }
                _schedule();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: basemap.urlTemplate,
                userAgentPackageName: 'uz.kadastr.kadastr',
                tileProvider: _tiles,
                maxNativeZoom: basemap.maxNativeZoom,
                maxZoom: 20,
                // Surishda ekrandan chiqqan tile'lar biroz saqlanadi —
                // orqaga qaytganda oq katak "yonib-o'chmaydi".
                keepBuffer: 4,
                panBuffer: 1,
                tileDisplay: const TileDisplay.fadeIn(
                  duration: Duration(milliseconds: 120),
                ),
              ),
              if (polygons.isNotEmpty)
                PolygonLayer<NgisParcel>(
                  polygons: polygons,
                  hitNotifier: _hits,
                  polygonLabels: _labels,
                  drawLabelsLast: true,
                ),
              // Joylashuv uchastkalar USTIDA chiziladi — aks holda zich
              // mahallada chegaralar ostida ko'rinmay qolardi.
              if (me != null && accuracy != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: me,
                      radius: accuracy,
                      useRadiusInMeter: true,
                      color: const Color(0x261A73E8),
                      borderColor: const Color(0x591A73E8),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              if (me != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: me,
                      width: 22,
                      height: 22,
                      child: const _MyLocationDot(),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.bottomRight,
                child: _Attribution(text: basemap.attribution),
              ),
            ],
          ),
        ),
        if (widget.interactive && !_detailed)
          Positioned(
            left: 12,
            // O'ng chekka bo'sh qoldiriladi: masshtab tugmalari o'sha yerda
            // turadi va yo'riqnoma ular ostiga kirib ketardi.
            right: 64,
            top: 12,
            child: Center(
              child: _ZoomHint(
                text: tr(
                  Localizations.localeOf(context),
                  'services.ai.parcel.zoom_in',
                ),
              ),
            ),
          ),
        if (busy)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2.5),
          ),
      ],
    );
  }
}

/// "Men shu yerdaman" nuqtasi — xaritalardagi odatiy ko'k dog'.
///
/// Oq halqa va soya ATAYLAB: sun'iy yo'ldosh tasviri ustida sof ko'k nuqta
/// yo'qolib ketadi, oq halqa esa uni har qanday fonda ajratib turadi.
class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Yaqinlashtiring" yo'riqnomasi — chegaralar hali chizilmaydigan masshtabda.
class _ZoomHint extends StatelessWidget {
  const _ZoomHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.zoom_in, size: 17, color: Colors.white),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 12,
                  height: 1.25,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bitta qatlam uchun yuklangan maydon va undagi uchastkalar.
class _LayerShot {
  const _LayerShot({required this.bounds, required this.parcels});

  final LatLngBounds bounds;
  final List<NgisParcel> parcels;

  /// Ko'rinish shu maydon ichidami — shunda qayta so'rash shart emas.
  bool covers(LatLngBounds visible) =>
      bounds.west <= visible.west &&
      bounds.east >= visible.east &&
      bounds.south <= visible.south &&
      bounds.north >= visible.north;
}

/// Tasvir manbasi yozuvi — provayder shartlari talab qiladi.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.only(right: 2, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        color: const Color(0x99FFFFFF),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'MTSText',
            fontSize: 8.5,
            height: 1.1,
            color: Color(0xFF44494C),
          ),
        ),
      ),
    );
  }
}
