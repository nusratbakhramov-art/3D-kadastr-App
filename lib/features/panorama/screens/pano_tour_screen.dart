/// 360° «house tour» — bir nechta panorama bo'ylab yurish va ularni
/// bir-biriga bog'lash.
///
/// Ikki rejim, BITTA ekran:
///
///  * **yurish** (`editable: false`) — e'lonni ko'rgan odam tugmalarni
///    bosib xonadan xonaga o'tadi;
///  * **tahrirlash** (`editable: true`) — e'lon egasi sehrgarda tugma
///    qo'yadi va oladi.
///
/// Bitta ekran qilingani ataylab: ikkitasi bo'lsa egasi o'zi yasagan
/// turni xaridor ko'radigan holatda sinay olmasdi va tugmani noto'g'ri
/// joyga qo'yganini faqat e'lon chiqqandan keyin bilardi.
///
/// ⚠️ XOTIRA. 3072×1536 panorama dekod qilinganda ~19 MB egallaydi,
/// ya'ni 8 xonali turni butunlay keshda ushlash 150 MB bo'lardi. Shu
/// sababli ayni paytda FAQAT BITTA tasvir dekod qilingan holda turadi va
/// o'tishda eskisi darhol bo'shatiladi. Narxi — o'tishda qisqa kutish;
/// muqobili — kam xotirali telefonda ilovaning o'lishi.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../bozor/models/tour_link.dart';
import '../../settings/settings_state.dart' show localeNotifier;
import '../render/pano_sphere.dart';

/// Turdagi bitta panorama — tasvir QAYERDAN olinishi.
///
/// [ref] — havolalar ishlatadigan identifikator: sehrgarda qurilma
/// yo'li, e'lon detalida S3 kaliti. Tasvirning o'zi esa mos ravishda
/// fayldan yoki tarmoqdan keladi.
@immutable
class TourPano {
  const TourPano({required this.ref, this.file, this.url, this.thumbUrl})
    : assert(file != null || url != null, 'fayl yoki url kerak');

  /// `TourLink.from` / `TourLink.to` shu qiymat bilan solishtiriladi.
  final String ref;

  final String? file;
  final String? url;

  /// Tanlash varag'idagi eskiz uchun — bo'lmasa [url] ishlatiladi.
  final String? thumbUrl;

  bool get isNetwork => file == null;
}

class PanoTourScreen extends StatefulWidget {
  const PanoTourScreen({
    super.key,
    required this.panoramas,
    required this.links,
    this.initialIndex = 0,
    this.editable = false,
    this.onChanged,
  });

  final List<TourPano> panoramas;
  final List<TourLink> links;
  final int initialIndex;

  /// Tugma qo'shish/olib tashlash mumkinmi.
  final bool editable;

  /// Har o'zgarishdan keyin TO'LIQ ro'yxat bilan chaqiriladi.
  ///
  /// To'liq ro'yxat — chunki chaqiruvchi uni qoralamaga yozadi va
  /// qo'shimcha/o'chirishni alohida kuzatib turishi kerak emas.
  final ValueChanged<List<TourLink>>? onChanged;

  @override
  State<PanoTourScreen> createState() => _PanoTourScreenState();
}

class _PanoTourScreenState extends State<PanoTourScreen> {
  late int _index = widget.initialIndex.clamp(
    0,
    widget.panoramas.isEmpty ? 0 : widget.panoramas.length - 1,
  );
  late List<TourLink> _links = List<TourLink>.of(widget.links);

  ui.Image? _image;
  bool _loading = true;
  String? _error;

  /// Yuklanayotgan panorama indeksi — javob kech kelsa tashlab yuborish
  /// uchun. Foydalanuvchi tez-tez o'tsa, birinchi yuklama ikkinchisidan
  /// KEYIN qaytishi mumkin va ekranda noto'g'ri xona qolardi.
  int _loadToken = 0;

  double _yawDeg = 0;
  double _pitchDeg = 0;
  double _fovDeg = kInitialFovDeg;

  double _yawAtStart = 0;
  double _pitchAtStart = 0;
  double _fovAtStart = kInitialFovDeg;
  Offset _focalAtStart = Offset.zero;

  Locale get _l => localeNotifier.value;
  String _t(String k) => tr(_l, k);

  TourPano get _current => widget.panoramas[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.panoramas.isEmpty) {
      setState(() {
        _loading = false;
        _error = _t('bozor.pano.view.err');
      });
      return;
    }
    final int token = ++_loadToken;
    final TourPano src = _current;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final Uint8List bytes;
      if (src.isNetwork) {
        final res = await http.get(Uri.parse(src.url!));
        if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
        bytes = res.bodyBytes;
      } else {
        final f = File(src.file!);
        // ⚠️ Bu holat HAQIQATAN uchraydi va uni «ochib bo'lmadi» deb
        // ko'rsatish foydalanuvchini ham, bizni ham adashtiradi: fayl
        // qoralamada bor, lekin diskda yo'q. Sabab aytilsin.
        if (!f.existsSync()) throw const FileSystemException('fayl topilmadi');
        bytes = await f.readAsBytes();
      }

      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();

      // Boshqa panoramaga o'tib bo'lingan yoki ekran yopilgan — bu
      // tasvir endi keraksiz va uni SHU YERDA bo'shatish shart, aks
      // holda u hech kimga tegishli bo'lmagan 19 MB bo'lib qolardi.
      if (!mounted || token != _loadToken) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = frame.image;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        // ⚠️ SABAB YOZILADI. Ilgari uch xil nosozlik — fayl yo'qolgan,
        // server rad etgan, JPEG buzuq — bitta matn berardi, ya'ni
        // qurilmadagi xabardan nima bo'lganini aniqlash IMKONSIZ edi.
        // Matn qisqa va aniq: uni foydalanuvchi o'qiydi va bizga aytadi.
        _error = '${_t('bozor.pano.view.err')}\n${_reason(e)}';
      });
    }
  }

  /// Nosozlikning bir qatorlik sababi.
  String _reason(Object e) => switch (e) {
    FileSystemException() => _t('bozor.pano.view.err_missing'),
    StateError(:final message) when message.startsWith('HTTP') =>
      '${_t('bozor.pano.view.err_network')} ($message)',
    SocketException() || HttpException() => _t('bozor.pano.view.err_network'),
    // Baytlar keldi-yu, tasvir chiqmadi — fayl buzuq yoki JPEG emas.
    _ => _t('bozor.pano.view.err_decode'),
  };

  void _goTo(int index, {double? yaw}) {
    if (index < 0 || index >= widget.panoramas.length || index == _index) {
      return;
    }
    setState(() {
      _index = index;
      // Yangi xonada o'tib kelgan yo'nalishga qarab turamiz — odam
      // eshikdan kirganda orqasiga emas, oldiga qaraydi.
      if (yaw != null) _yawDeg = yaw;
      _pitchDeg = 0;
    });
    unawaited(_load());
  }

  int _indexOf(String ref) =>
      widget.panoramas.indexWhere((TourPano p) => p.ref == ref);

  // ── Ishoratlar ────────────────────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails d) {
    _yawAtStart = _yawDeg;
    _pitchAtStart = _pitchDeg;
    _fovAtStart = _fovDeg;
    _focalAtStart = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final Offset delta = d.localFocalPoint - _focalAtStart;
    final double fov = _fovAtStart;
    final double hFov = fov * (size.width / size.height);
    setState(() {
      _fovDeg = (_fovAtStart / d.scale).clamp(kMinFovDeg, kMaxFovDeg);
      _yawDeg = _yawAtStart - delta.dx / size.width * hFov;
      _pitchDeg = (_pitchAtStart + delta.dy / size.height * fov).clamp(
        -kMaxPitchDeg,
        kMaxPitchDeg,
      );
    });
  }

  // ── Tahrirlash ────────────────────────────────────────────────────────
  void _emit() => widget.onChanged?.call(List<TourLink>.unmodifiable(_links));

  Future<void> _addHere() async {
    final String from = _current.ref;
    final List<TourLink> mine = linksFrom(_links, from);

    if (mine.length >= kMaxTourLinksPerPanorama) {
      _toast(_t('bozor.pano.tour.limit'));
      return;
    }
    // Ustma-ust tushgan tugmani bosib bo'lmaydi — oldindan aytamiz.
    final TourLink? near = overlappingLink(_links, from, _yawDeg % 360, _pitchDeg);
    if (near != null) {
      _toast(_t('bozor.pano.tour.too_close'));
      return;
    }

    final _PickResult? picked = await showModalBottomSheet<_PickResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _TargetPicker(
        panoramas: widget.panoramas,
        currentRef: from,
        // Allaqachon bog'langanini QAYTA tanlab bo'lmaydi: server takror
        // juftlikni rad etadi va butun e'lon yuborilmay qolardi.
        linkedRefs: {for (final TourLink l in mine) l.to},
        locale: _l,
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _links = <TourLink>[
        ..._links,
        TourLink(
          from: from,
          to: picked.ref,
          yawDeg: _yawDeg % 360,
          pitchDeg: _pitchDeg,
          label: picked.label,
        ),
      ];
    });
    _emit();
  }

  Future<void> _tapHotspot(TourLink link) async {
    final int target = _indexOf(link.to);
    if (!widget.editable) {
      // Yurish rejimida tugma FAQAT o'tkazadi.
      if (target >= 0) _goTo(target, yaw: link.yawDeg);
      return;
    }

    final String? action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1B2124),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.login_rounded, color: Colors.white70),
              title: Text(
                _t('bozor.pano.tour.go'),
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.of(ctx).pop('go'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFE06C6C),
              ),
              title: Text(
                _t('bozor.pano.tour.remove'),
                style: const TextStyle(color: Color(0xFFE06C6C)),
              ),
              onTap: () => Navigator.of(ctx).pop('remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;

    if (action == 'remove') {
      setState(() => _links = <TourLink>[
        for (final TourLink l in _links)
          if (l != link) l,
      ]);
      _emit();
    } else if (action == 'go' && target >= 0) {
      _goTo(target, yaw: link.yawDeg);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ── Qurish ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final List<String> refs = <String>[
      for (final TourPano p in widget.panoramas) p.ref,
    ];
    final List<String> orphans = unreachablePanoramas(refs, _links);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext _, BoxConstraints c) {
              final Size size = Size(c.maxWidth, c.maxHeight);
              return GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: (ScaleUpdateDetails d) =>
                    _onScaleUpdate(d, size),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (_image != null)
                      CustomPaint(
                        size: size,
                        painter: SpherePainter(
                          image: _image!,
                          yawDeg: _yawDeg,
                          pitchDeg: _pitchDeg,
                          fovDeg: _fovDeg,
                        ),
                      ),
                    if (_image != null) ..._hotspots(size),
                  ],
                ),
              );
            },
          ),

          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white70)),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ),

          // Tahrirlashda markazdagi nishon — tugma AYNAN shu yerga
          // qo'yiladi. Barmoq bilan bosishdan farqi: barmoq nuqtani
          // to'sadi va qayerga tushganini ko'rib bo'lmaydi.
          if (widget.editable && _image != null)
            const IgnorePointer(child: Center(child: _Reticle())),

          _topBar(orphans),
          if (widget.editable && _image != null) _bottomBar(),
        ],
      ),
    );
  }

  /// Joriy panoramadan chiqadigan havolalarni EKRANGA joylaydi.
  ///
  /// Widget bo'lib qo'yiladi, chizilmaydi — tugma bosiladigan narsa va
  /// `CustomPaint` ichida bosishni o'zimiz hisoblashimiz kerak bo'lardi.
  List<Widget> _hotspots(Size size) {
    final ViewBasis? basis = ViewBasis.of(
      size: size,
      yawDeg: _yawDeg,
      pitchDeg: _pitchDeg,
      fovDeg: _fovDeg,
    );
    if (basis == null) return const <Widget>[];

    const double r = 26;
    final out = <Widget>[];
    for (final TourLink l in linksFrom(_links, _current.ref)) {
      final Offset? at = basis.projectDeg(l.yawDeg, l.pitchDeg);
      // `null` — kamera ORQASIDA. Qisib qo'yish tugmani oldinda
      // ko'rsatardi, ya'ni orqangizdagi xonaning eshigi ro'parangizda
      // turardi.
      if (at == null) continue;
      if (at.dx < -r ||
          at.dy < -r ||
          at.dx > size.width + r ||
          at.dy > size.height + r) {
        continue;
      }
      out.add(
        Positioned(
          left: at.dx - r,
          top: at.dy - r,
          width: r * 2,
          height: r * 2,
          child: _Hotspot(
            label: l.label,
            editing: widget.editable,
            onTap: () => _tapHotspot(l),
          ),
        ),
      );
    }
    return out;
  }

  Widget _topBar(List<String> orphans) => Positioned(
    top: MediaQuery.of(context).padding.top + 8,
    left: 8,
    right: 8,
    child: Row(
      children: <Widget>[
        _RoundBtn(
          icon: Icons.close_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        if (widget.panoramas.length > 1)
          _Chip(text: '${_index + 1} / ${widget.panoramas.length}'),
        if (widget.editable && orphans.isNotEmpty) ...<Widget>[
          const SizedBox(width: 8),
          // Turdan yetib bo'lmaydigan panorama — e'londa bor, lekin
          // yurib borib bo'lmaydi. Xato emas, lekin deyarli har doim
          // unutilgan havola.
          _Chip(
            text: _t(
              'bozor.pano.tour.unreachable',
            ).replaceAll('{n}', '${orphans.length}'),
            warn: true,
          ),
        ],
      ],
    ),
  );

  Widget _bottomBar() {
    final bool alone = widget.panoramas.length < 2;
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _t(alone ? 'bozor.pano.tour.need_two' : 'bozor.pano.tour.aim'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: alone ? null : hapticTap(_addHere),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.splashGreen,
                disabledBackgroundColor: Colors.white24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _t('bozor.pano.tour.add'),
                style: const TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Kichik qismlar ──────────────────────────────────────────────────────────

class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 56,
    child: CustomPaint(painter: _ReticlePainter()),
  );
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.9);
    // Qora hoshiya: oq nishon oq devorda ko'rinmay qolardi.
    final Paint halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.black.withValues(alpha: 0.35);
    canvas.drawCircle(c, 18, halo);
    canvas.drawCircle(c, 18, ring);
    canvas.drawCircle(c, 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => false;
}

class _Hotspot extends StatelessWidget {
  const _Hotspot({required this.onTap, required this.editing, this.label});

  final VoidCallback onTap;
  final bool editing;
  final String? label;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: hapticTap(onTap),
    behavior: HitTestBehavior.opaque,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(
              color: editing ? AppColors.splashGreen : Colors.white,
              width: 2,
            ),
          ),
          child: Icon(
            editing ? Icons.edit_location_alt_rounded : Icons.arrow_forward_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        if (label != null)
          Positioned(
            bottom: -22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.45),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: warn
          ? const Color(0xFFB4791F).withValues(alpha: 0.85)
          : Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}

class _PickResult {
  const _PickResult(this.ref, this.label);

  final String ref;
  final String? label;
}

/// «Qaysi panoramaga o'tadi?» varag'i.
class _TargetPicker extends StatefulWidget {
  const _TargetPicker({
    required this.panoramas,
    required this.currentRef,
    required this.linkedRefs,
    required this.locale,
  });

  final List<TourPano> panoramas;
  final String currentRef;

  /// Shu panoramadan ALLAQACHON bog'langanlari — qayta tanlab bo'lmaydi.
  final Set<String> linkedRefs;
  final Locale locale;

  @override
  State<_TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<_TargetPicker> {
  final TextEditingController _label = TextEditingController();
  String? _selected;

  String _t(String k) => tr(widget.locale, k);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF1B2124),
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 16,
      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _t('bozor.pano.tour.pick_title'),
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.panoramas.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (BuildContext _, int i) {
              final TourPano p = widget.panoramas[i];
              // O'ziga havola ma'nosiz — bosilganda hech narsa
              // o'zgarmaydi va foydalanuvchi tugma buzuq deb o'ylaydi.
              if (p.ref == widget.currentRef) return const SizedBox.shrink();
              final bool linked = widget.linkedRefs.contains(p.ref);
              return _Tile(
                source: p,
                index: i,
                disabled: linked,
                disabledText: _t('bozor.pano.tour.linked'),
                selected: _selected == p.ref,
                onTap: linked
                    ? null
                    : () => setState(() => _selected = p.ref),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _label,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            counterText: '',
            hintText: _t('bozor.pano.tour.label_hint'),
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(
                    _PickResult(
                      _selected!,
                      _label.text.trim().isEmpty ? null : _label.text.trim(),
                    ),
                  ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.splashGreen,
              disabledBackgroundColor: Colors.white24,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _t('bozor.pano.tour.confirm'),
              style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.source,
    required this.index,
    required this.selected,
    required this.disabled,
    required this.disabledText,
    required this.onTap,
  });

  final TourPano source;
  final int index;
  final bool selected;
  final bool disabled;
  final String disabledText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String? thumb = source.thumbUrl ?? source.url;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Container(
          width: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.splashGreen : Colors.white24,
              width: selected ? 2.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (source.isNetwork)
                Image.network(thumb!, fit: BoxFit.cover, errorBuilder: _broken)
              else
                Image.file(
                  File(source.file!),
                  fit: BoxFit.cover,
                  errorBuilder: _broken,
                ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    disabled ? disabledText : '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _broken(BuildContext _, Object _, StackTrace? _) =>
      const ColoredBox(
        color: Colors.white10,
        child: Icon(Icons.broken_image_outlined, color: Colors.white38),
      );
}
