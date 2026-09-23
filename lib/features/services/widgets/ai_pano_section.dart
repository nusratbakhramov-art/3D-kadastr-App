/// AI Baholash «Hujjatlar» qadami — «Obyekt tasviri» kartasining 360° tabi.
///
/// Karta o'zi (sarlavha, Rasmlar | 360° xona almashtirgichi) intake ekranida;
/// bu widget faqat 360° TAB TANASI: xonalar to'ri, «+ Xona qo'shish», tur.
///
/// Bozor e'lonining 360° oqimi (6/7-qadam) bilan BIR XIL capture: nativ
/// suratga olish → telefonda tikish → ko'rib chiqish → yuklash
/// (`PanoCaptureFlow`). Farqi faqat yuklash manzilida
/// (`/ai-valuations/upload`, category=panorama — [uploadAiPanorama]) va
/// holatning qayerda turishida ([AiBaholashBundle]).
///
/// XONALAR TO'RI, LENTA EMAS. Egasi odatda HAR xonani suratga oladi (3-4 va
/// undan ko'p) — gorizontal lentada uchinchisi ekrandan chiqib ketardi va
/// nechta xona qo'shilgani ko'rinmasdi. 2 ustunli to'rda hammasi ko'rinadi.
///
/// Tur: iOS 16+ da nativ (SceneKit, «Yangi xona — hozir tushirish» bilan),
/// aks holda Dart `PanoTourScreen`. Ikkalasida ham tugmalar (havolalar)
/// tahrirlanadi va `bundle.tourLinks` ga yoziladi — Narxlash
/// ma'lumotnomasidagi 360° QR shu turni ko'rsatadi.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../auth/widgets/auth_toast.dart';
import '../../bozor/data/tour_native.dart';
import '../../bozor/models/tour_link.dart';
import '../../panorama/data/pano_capture_channel.dart';
import '../../panorama/screens/pano_capture_flow.dart';
import '../../panorama/screens/pano_tour_screen.dart';
import '../data/ai_pano_upload.dart';
import '../models/ai_baholash_bundle.dart';
import 'room_picker_sheet.dart';

/// Backend `panorama_keys` chegarasi (`max_length=20`).
const int kMaxAiPanoramas = 20;

class AiPanoRooms extends StatefulWidget {
  const AiPanoRooms({
    super.key,
    required this.bundle,
    required this.onChanged,
    required this.emptyBuilder,
    this.openCapture = openPanoCapture,
  });

  final AiBaholashBundle bundle;

  /// Bundle o'zgardi — ota ekran shartni qayta hisoblaydi va qoralamani saqlaydi.
  final VoidCallback onChanged;

  /// Hali xona yo'q — ota kartaning bo'sh «drop zone» i (rasmlar tabi bilan
  /// bir xil ko'rinsin). [onAdd] — birinchi xonani suratga olish.
  final Widget Function(VoidCallback onAdd) emptyBuilder;

  /// Testlar uchun almashtiriladi.
  final Future<PanoOutcome?> Function(
    BuildContext context, {
    String? resumeDir,
    void Function(String dir)? onCaptured,
    void Function(String dir)? onDiscarded,
    PanoUploadFn? upload,
  })
  openCapture;

  @override
  State<AiPanoRooms> createState() => _AiPanoRoomsState();
}

/// Tushirilgan, lekin YUKLANMAGAN xona (tikish/yuklash yiqildi). Faqat shu
/// ekran yashaguncha turadi: kadrlar diskda, bosilsa davom ettiriladi.
class _SavedPano {
  _SavedPano(this.dir, this.name);
  final String dir;
  final String? name;
}

class _AiPanoRoomsState extends State<AiPanoRooms> {
  AiBaholashBundle get _b => widget.bundle;

  PanoCaptureMode? _captureMode;
  bool _probed = false;
  bool _nativeViewer = false;
  bool _busy = false;
  final List<_SavedPano> _saved = [];

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final mode = await PanoCaptureChannel.preferredCaptureMode();
    final viewer = await PanoCaptureChannel.isViewerSupported();
    if (!mounted) return;
    setState(() {
      _captureMode = mode;
      _nativeViewer = viewer;
      _probed = true;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    AuthToasts.show(context, message: msg, variant: AuthToastVariant.error);
  }

  void _changed() {
    if (mounted) setState(() {});
    widget.onChanged();
  }

  String _roomName(Locale l, String key) =>
      _b.panoramaNames[key] ??
      tr(
        l,
        'bozor.pano.tour.room_n',
      ).replaceFirst('%d', '${_b.panoramaKeys.indexOf(key) + 1}');

  /// Telefonda fayli bor (tur va eskiz uchun) xonalar.
  List<String> get _localKeys => [
    for (final k in _b.panoramaKeys)
      if (_hasFile(_b.panoramaPaths[k])) k,
  ];

  static bool _hasFile(String? p) =>
      p != null && p.isNotEmpty && File(p).existsSync();

  int get _roomCount => _b.panoramaKeys.length + _saved.length;

  // ── Capture ──────────────────────────────────────────────────────────

  Future<void> _addRoom() async {
    final l = Localizations.localeOf(context);
    if (_probed && _captureMode == null) {
      _toast(tr(l, 'services.ai.intake.pano_unavailable'));
      return;
    }
    if (_roomCount >= kMaxAiPanoramas) {
      _toast(
        tr(
          l,
          'services.ai.intake.max_photos',
        ).replaceAll(r'$n', '$kMaxAiPanoramas'),
      );
      return;
    }
    final choice = await showRoomPickerSheet(
      context,
      title: tr(l, 'bozor.pano.rooms.name_title'),
      hint: tr(l, 'bozor.pano.rooms.name_hint'),
    );
    if (!mounted || choice == null) return;
    await _capture(name: choice.label(l));
  }

  /// Oqimni yuritadi. Qaytadi: yangi kalit yoki `null`.
  Future<String?> _capture({String? name, _SavedPano? resume}) async {
    if (_busy) return null;
    _busy = true;
    try {
      final outcome = await widget.openCapture(
        context,
        resumeDir: resume?.dir,
        upload: uploadAiPanorama,
      );
      if (!mounted) return null;
      switch (outcome) {
        case PanoUploaded(:final storageKey, :final url):
          if (resume != null) _saved.remove(resume);
          _b.panoramaKeys.add(storageKey);
          _b.panoramaPaths[storageKey] = url; // lokal nusxa yo'li
          final n = name ?? resume?.name;
          if (n != null && n.trim().isNotEmpty) {
            _b.panoramaNames[storageKey] = n.trim();
          }
          _changed();
          return storageKey;
        case PanoSaved(:final dir):
          if (resume == null) {
            _saved.add(_SavedPano(dir, name));
          }
          setState(() {});
          return null;
        case null:
          return null;
      }
    } finally {
      _busy = false;
    }
  }

  // ── Remove ───────────────────────────────────────────────────────────

  void _remove(String key) {
    HapticFeedback.lightImpact();
    _b.panoramaKeys.remove(key);
    _b.panoramaNames.remove(key);
    deleteAiPanoramaCopy(_b.panoramaPaths.remove(key));
    _b.tourLinks.removeWhere((l) => l.from == key || l.to == key);
    _changed();
  }

  void _removeSaved(_SavedPano s) {
    HapticFeedback.lightImpact();
    setState(() => _saved.remove(s));
    final d = Directory(s.dir);
    if (d.existsSync()) {
      d.delete(recursive: true).ignore();
    }
  }

  // ── Tour ─────────────────────────────────────────────────────────────

  Future<void> _openTour(String startKey) async {
    final ready = _localKeys;
    if (ready.isEmpty) return;
    final start = ready.contains(startKey) ? startKey : ready.first;
    if (_nativeViewer) {
      await _openNativeTour(ready, start);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PanoTourScreen(
          panoramas: <TourPano>[
            for (final k in ready) TourPano(ref: k, file: _b.panoramaPaths[k]),
          ],
          links: _b.tourLinks,
          initialIndex: ready.indexOf(start),
          editable: true,
          onChanged: (List<TourLink> links) {
            _b.tourLinks
              ..clear()
              ..addAll(links);
            _changed();
          },
        ),
      ),
    );
  }

  /// Nativ tur. «Yangi xona — hozir tushirish» tanlansa tur yopiladi, xona
  /// tushiriladi, ikki tomonlama tugma qo'yiladi va tur YANGI xonada qayta
  /// ochiladi — Bozor `_openNativeTour` bilan bir xil sikl.
  Future<void> _openNativeTour(List<String> ready, String startKey) async {
    var start = startKey;
    while (mounted) {
      final l = Localizations.localeOf(context);
      final res = await PanoCaptureChannel.tour(
        context,
        panoramas: <PanoTourRoom>[
          for (final k in ready)
            PanoTourRoom(
              key: k,
              name: _roomName(l, k),
              path: _b.panoramaPaths[k],
            ),
        ],
        links: tourLinksToChannel(_b.tourLinks),
        startKey: start,
        editable: true,
      );
      if (!mounted || res == null) return;
      _b.tourLinks
        ..clear()
        ..addAll(tourLinksFromChannel(res.links));
      _changed();
      final action = res.newRoom;
      if (action == null) return;

      if (_roomCount >= kMaxAiPanoramas) return;
      final choice = await showRoomPickerSheet(
        context,
        title: tr(l, 'bozor.pano.rooms.name_title'),
        hint: tr(l, 'bozor.pano.rooms.name_hint'),
      );
      if (!mounted) return;
      if (choice == null) {
        start = action.fromKey;
        continue;
      }
      final key = await _capture(name: choice.label(l));
      if (!mounted) return;
      if (key == null) {
        start = action.fromKey;
        continue;
      }
      final merged = mergeNewRoomLinks(_b.tourLinks, action, key);
      _b.tourLinks
        ..clear()
        ..addAll(merged);
      _changed();
      ready.add(key);
      start = key;
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    if (_roomCount == 0) {
      if (_probed && _captureMode == null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            tr(l, 'services.ai.intake.pano_unavailable'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 13,
              color: muted,
            ),
          ),
        );
      }
      return widget.emptyBuilder(_addRoom);
    }

    final canAdd = _captureMode != null && _roomCount < kMaxAiPanoramas;
    final tiles = <Widget>[
      for (final s in _saved)
        _RoomTile(
          name: s.name ?? '',
          file: null,
          failed: true,
          label: tr(l, 'services.ai.intake.pano_saved'),
          onTap: () => _capture(resume: s),
          onRemove: () => _removeSaved(s),
        ),
      for (final k in _b.panoramaKeys)
        _RoomTile(
          name: _roomName(l, k),
          file: _hasFile(_b.panoramaPaths[k]) ? _b.panoramaPaths[k] : null,
          label: tr(l, 'services.ai.intake.uploaded'),
          onTap: _hasFile(_b.panoramaPaths[k]) ? () => _openTour(k) : null,
          onRemove: () => _remove(k),
        ),
      if (canAdd)
        _AddRoomTile(
          label: tr(l, 'services.ai.intake.pano_add_room'),
          onTap: _addRoom,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = 10.0;
            final w = (c.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in tiles) SizedBox(width: w, child: t),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_localKeys.isNotEmpty)
              TextButton.icon(
                onPressed: () => _openTour(_localKeys.first),
                icon: const Icon(Icons.threesixty_rounded, size: 18),
                label: Text(tr(l, 'services.ai.intake.pano_tour')),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.splashGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  textStyle: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            const Spacer(),
            Text(
              tr(
                l,
                'services.ai.intake.rooms_count',
              ).replaceAll(r'$n', '${_b.panoramaKeys.length}'),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 12,
                color: muted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Bitta xona: 2:1 eskiz (panoramaning o'zi), ostida nomi.
class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.name,
    required this.file,
    required this.label,
    required this.onRemove,
    this.onTap,
    this.failed = false,
  });

  final String name;
  final String? file;

  /// Eskiz o'rnidagi yozuv (fayl yo'q bo'lsa): «Yuklangan» yoki «Yuklanmadi…».
  final String label;
  final VoidCallback? onTap;
  final VoidCallback onRemove;
  final bool failed;

  static const _red = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBg = isDark ? const Color(0xFF14181A) : const Color(0xFFF1F2F4);
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    final Widget image = file != null
        ? Image.file(
            File(file!),
            fit: BoxFit.cover,
            cacheWidth: 480,
            errorBuilder: (_, _, _) => ColoredBox(
              color: chipBg,
              child: Icon(Icons.broken_image_outlined, size: 22, color: muted),
            ),
          )
        : ColoredBox(
            color: chipBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    failed ? Icons.refresh_rounded : Icons.cloud_done_outlined,
                    size: 22,
                    color: failed ? _red : muted,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      color: failed ? _red : muted,
                    ),
                  ),
                ],
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: failed ? _red : border),
                    ),
                    child: image,
                  ),
                ),
              ),
              if (file != null)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '360°',
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 5,
                top: 5,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF14181A)
                          : Colors.white.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded, size: 14, color: muted),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

/// To'rning oxiridagi «+ Xona qo'shish» — xona bilan bir xil o'lcham.
class _AddRoomTile extends StatelessWidget {
  const _AddRoomTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.splashGreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 2,
          child: Material(
            color: accent.withValues(alpha: isDark ? 0.07 : 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: accent.withValues(alpha: 0.55)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, size: 24, color: accent),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: isDark ? Colors.white : AppColors.textBlack,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Nom qatori bilan tenglashtirish — to'r qatorlari bir tekis tursin.
        const SizedBox(height: 5 + 17),
      ],
    );
  }
}
