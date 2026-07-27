/// Step 4 of 3D Kadastr — intake (hujjat va rasmlar).
///
/// Mirrors the AI Baholash intake (`ai_intake_screen.dart`) **without** the
/// owner passport/ID section. Three sections on one scrollable screen:
///   • Property photos (inside/outside, 1-15)
///   • Kadastr documents (1-20)
///   • Floor + rooms breakdown
///
/// Uses the same per-file (ChatGPT-style) upload UI as AI Baholash: each picked
/// file is its own tile that uploads independently to `/3d-kadastr-jobs/upload`
/// and can be retried / removed on its own. The returned keys are stored on the
/// bundle. "Davom etish" proceeds to the LiDAR scan step.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../auth/widgets/auth_toast.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../../settings/settings_state.dart';
import '../../api_ai_upload_service.dart';
import '../../models/ai_baholash_bundle.dart' show AiRoom, RoomKind;
import '../../models/kadastr_3d_bundle.dart';
import '../../widgets/file_preview_gallery.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/step_progress_bar.dart';
import '../scan_lidar_screen.dart';

/// Backend route for 3D Kadastr uploads (vs AI Baholash's default).
const String _kUploadEndpoint = '/3d-kadastr-jobs/upload';

class K3dIntakeScreen extends StatefulWidget {
  const K3dIntakeScreen({super.key, required this.bundle});

  final Kadastr3dBundle bundle;

  @override
  State<K3dIntakeScreen> createState() => _K3dIntakeScreenState();
}

class _K3dIntakeScreenState extends State<K3dIntakeScreen> {
  final AiUploadService _uploads = AiUploadService();
  final ImagePicker _imagePicker = ImagePicker();

  // Per-FILE upload state (ChatGPT-style): each picked file is its own tile that
  // uploads independently and can be retried / removed on its own. The bundle's
  // server-key lists are kept in sync with the items that finished uploading.
  final List<_UploadItem> _photoItems = [];
  final List<_UploadItem> _kadastrItems = [];

  bool get _anyUploading =>
      _photoItems.any((i) => i.status == _UpStatus.uploading) ||
      _kadastrItems.any((i) => i.status == _UpStatus.uploading);

  final TextEditingController _floorCtrl = TextEditingController();
  final TextEditingController _totalFloorsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.bundle.floor != null) {
      _floorCtrl.text = '${widget.bundle.floor}';
    }
    if (widget.bundle.totalFloors != null) {
      _totalFloorsCtrl.text = '${widget.bundle.totalFloors}';
    }
    // Restore already-uploaded tiles when the user returns to edit — the bundle
    // keeps local paths + server keys index-aligned (see _sync below).
    _rehydrate(_photoItems, widget.bundle.imagePaths, widget.bundle.imageKeys);
    _rehydrate(
      _kadastrItems,
      widget.bundle.kadastrPaths,
      widget.bundle.kadastrKeys,
    );
  }

  void _rehydrate(
    List<_UploadItem> items,
    List<String> paths,
    List<String> keys,
  ) {
    final n = paths.length < keys.length ? paths.length : keys.length;
    for (var i = 0; i < n; i++) {
      items.add(
        _UploadItem(paths[i])
          ..key = keys[i]
          ..status = _UpStatus.done,
      );
    }
  }

  @override
  void dispose() {
    _uploads.dispose();
    _floorCtrl.dispose();
    _totalFloorsCtrl.dispose();
    super.dispose();
  }

  // Photos, kadastr docs, rooms, and both floor numbers are mandatory.
  // Backend caps total_floors at 200 — validate client-side for a friendly
  // hint instead of a raw 422.
  static const int _maxFloors = 200;

  bool get _ready =>
      !_anyUploading &&
      widget.bundle.imageKeys.isNotEmpty &&
      widget.bundle.kadastrKeys.isNotEmpty &&
      widget.bundle.rooms.isNotEmpty &&
      widget.bundle.floor != null &&
      widget.bundle.totalFloors != null &&
      widget.bundle.floor! >= 1 &&
      widget.bundle.totalFloors! >= 1 &&
      widget.bundle.totalFloors! <= _maxFloors &&
      widget.bundle.floor! <= widget.bundle.totalFloors!;

  String? get _missingHint {
    if (_ready) return null;
    final l = localeNotifier.value;
    if (_anyUploading) return tr(l, 'services.k3d.intake.uploading_files');
    final missing = <String>[];
    if (widget.bundle.imageKeys.isEmpty) {
      missing.add(tr(l, 'services.k3d.intake.missing_photo'));
    }
    if (widget.bundle.kadastrKeys.isEmpty) {
      missing.add(tr(l, 'services.k3d.intake.missing_kadastr'));
    }
    if (widget.bundle.rooms.isEmpty) {
      missing.add(tr(l, 'services.k3d.intake.missing_rooms'));
    }
    final f = widget.bundle.floor;
    final tf = widget.bundle.totalFloors;
    if (f == null || tf == null || f < 1 || tf < 1) {
      missing.add(tr(l, 'services.k3d.intake.missing_floor'));
    } else if (tf > _maxFloors) {
      return tr(l, 'services.k3d.intake.floor_max')
          .replaceAll(r'$max', '$_maxFloors');
    } else if (f > tf) {
      return tr(l, 'services.k3d.intake.floor_exceeds');
    }
    return tr(l, 'services.k3d.intake.required_suffix')
        .replaceAll(r'$items', missing.join(', '));
  }

  void _setFloor(String raw) {
    setState(() => widget.bundle.floor = int.tryParse(raw.trim()));
  }

  void _setTotalFloors(String raw) {
    setState(() => widget.bundle.totalFloors = int.tryParse(raw.trim()));
  }

  Future<String?> _token() async {
    final session = await const AuthStorage().loadSession();
    return session.token;
  }

  // Floating red error toast (top of screen, auto-dismiss) + a firm haptic —
  // not the default snackbar that covered the button.
  void _toast(String msg) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    AuthToasts.show(context, message: msg, variant: AuthToastVariant.error);
  }

  // ── Property photos (image_picker) ──────────────────────────────────
  Future<void> _addPhotos() async {
    final remaining = 15 - _photoItems.length;
    if (remaining <= 0) {
      _toast(tr(localeNotifier.value, 'services.k3d.intake.max_photos')
          .replaceAll(r'$n', '15'));
      return;
    }
    final List<XFile> picked =
        await _imagePicker.pickMultiImage(limit: remaining);
    if (picked.isEmpty) return;
    _enqueue(
      category: UploadCategory.propertyPhoto,
      items: _photoItems,
      paths: picked.map((x) => x.path).toList(),
      sync: _syncPhotoKeys,
    );
  }

  // ── Kadastr docs (file_picker: images + pdf) ────────────────────────
  Future<void> _addKadastr() => _pickDocs(
        category: UploadCategory.kadastr,
        items: _kadastrItems,
        maxTotal: 20,
        sync: _syncKadastrKeys,
      );

  Future<void> _pickDocs({
    required UploadCategory category,
    required List<_UploadItem> items,
    required int maxTotal,
    required VoidCallback sync,
  }) async {
    final remaining = maxTotal - items.length;
    if (remaining <= 0) {
      _toast(tr(localeNotifier.value, 'services.k3d.intake.max_files')
          .replaceAll(r'$n', '$maxTotal'));
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf', 'doc', 'docx', 'xls', 'xlsx',
        'jpg', 'jpeg', 'png', 'webp', 'heic',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .take(remaining)
        .toList();
    _enqueue(category: category, items: items, paths: paths, sync: sync);
  }

  // Create one "uploading" tile per newly-picked path (skipping dupes already in
  // the section), then upload each independently so one failure can't sink the
  // batch and each can be retried on its own.
  void _enqueue({
    required UploadCategory category,
    required List<_UploadItem> items,
    required List<String> paths,
    required VoidCallback sync,
  }) {
    final existing = items.map((i) => i.path).toSet();
    final fresh = <_UploadItem>[];
    setState(() {
      for (final p in paths) {
        if (existing.contains(p)) continue;
        final item = _UploadItem(p);
        items.add(item);
        fresh.add(item);
      }
    });
    for (final item in fresh) {
      _uploadOne(item, category, sync);
    }
  }

  Future<void> _uploadOne(
    _UploadItem item,
    UploadCategory category,
    VoidCallback sync,
  ) async {
    final token = await _token();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() {
        item.status = _UpStatus.failed;
        item.error = tr(localeNotifier.value, 'services.k3d.intake.auth_required');
      });
      return;
    }
    setState(() {
      item.status = _UpStatus.uploading;
      item.error = null;
    });
    try {
      final keys = await _uploads.upload(
        category: category,
        filePaths: [item.path],
        token: token,
        endpoint: _kUploadEndpoint,
      );
      if (!mounted) return;
      setState(() {
        item.key = keys.isNotEmpty ? keys.first : null;
        item.status = item.key != null ? _UpStatus.done : _UpStatus.failed;
        if (item.key == null) {
          item.error =
              tr(localeNotifier.value, 'services.k3d.intake.upload_failed');
        }
      });
    } on AiUploadException catch (e) {
      if (!mounted) return;
      // 400 = backend rejected this file (too big / wrong type / over the cap).
      setState(() {
        item.status = _UpStatus.failed;
        item.error = e.statusCode == 400
            ? tr(localeNotifier.value, 'services.k3d.intake.upload_rejected')
            : tr(localeNotifier.value, 'services.k3d.intake.upload_failed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        item.status = _UpStatus.failed;
        item.error =
            tr(localeNotifier.value, 'services.k3d.intake.upload_failed');
      });
    } finally {
      sync();
    }
  }

  void _retry(_UploadItem item, UploadCategory category, VoidCallback sync) {
    HapticFeedback.selectionClick();
    _uploadOne(item, category, sync);
  }

  void _removeItem(
    List<_UploadItem> items,
    _UploadItem item,
    VoidCallback sync,
  ) {
    HapticFeedback.lightImpact();
    setState(() => items.remove(item));
    sync();
  }

  // Keep the bundle's server-key lists (what gets submitted) in sync with the
  // items that finished uploading, preserving order.
  void _syncPhotoKeys() =>
      _sync(_photoItems, widget.bundle.imageKeys, widget.bundle.imagePaths);
  void _syncKadastrKeys() => _sync(
        _kadastrItems,
        widget.bundle.kadastrKeys,
        widget.bundle.kadastrPaths,
      );

  // Rebuild the bundle's server-key list AND the index-aligned local-path list
  // from the items that finished uploading — so a re-entered intake can restore
  // its tiles and the preview gallery works.
  void _sync(List<_UploadItem> items, List<String> keys, List<String> paths) {
    final done = items.where((i) => i.key != null).toList();
    keys
      ..clear()
      ..addAll(done.map((i) => i.key!));
    paths
      ..clear()
      ..addAll(done.map((i) => i.path));
    if (mounted) setState(() {});
  }

  // Tap a finished image tile → full-screen, swipeable gallery of this section's
  // images, opened at the tapped one.
  void _openPreview(List<_UploadItem> items, _UploadItem tapped) {
    final images = items.where((i) => _UploadItem.isImagePath(i.path)).toList();
    final start = images.indexOf(tapped);
    if (start < 0) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FilePreviewGallery(
          paths: images.map((i) => i.path).toList(),
          initialIndex: start,
        ),
      ),
    );
  }

  void _showMissing() {
    final msg = _missingHint;
    if (msg != null) _toast(msg);
  }

  Widget _buildSubmit(Locale l) {
    final button = ListingCtaButton(
      label: tr(l, 'services.k3d.continue'),
      enabled: _ready,
      onTap: _continue,
    );
    if (_ready) return button;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showMissing,
      child: button,
    );
  }

  void _continue() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanLidarScreen(bundle: widget.bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final b = widget.bundle;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ServiceAppBar(
                    title: tr(l, 'services.k3d.intake.appbar'),
                    subtitle: tr(l, 'services.k3d.intake.subtitle'),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(count: 6, activeIndex: 4),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _UploadCard(
                        title: tr(l, 'services.k3d.intake.object_photos'),
                        hint: tr(l, 'services.k3d.intake.object_photos_hint'),
                        icon: Icons.photo_camera_outlined,
                        emptyIcon: Icons.add_photo_alternate_outlined,
                        actionLabel: tr(l, 'services.k3d.intake.add_photos_cta'),
                        items: _photoItems,
                        maxFiles: 15,
                        onAdd: _addPhotos,
                        onRetry: (it) => _retry(
                          it,
                          UploadCategory.propertyPhoto,
                          _syncPhotoKeys,
                        ),
                        onRemove: (it) =>
                            _removeItem(_photoItems, it, _syncPhotoKeys),
                        onPreview: (it) => _openPreview(_photoItems, it),
                      ),
                      const SizedBox(height: 12),
                      _UploadCard(
                        title: tr(l, 'services.k3d.intake.kadastr_docs'),
                        hint: tr(l, 'services.k3d.intake.kadastr_docs_hint'),
                        icon: Icons.description_outlined,
                        emptyIcon: Icons.upload_file_outlined,
                        actionLabel: tr(l, 'services.k3d.intake.add_docs_cta'),
                        items: _kadastrItems,
                        maxFiles: 20,
                        onAdd: _addKadastr,
                        onRetry: (it) => _retry(
                          it,
                          UploadCategory.kadastr,
                          _syncKadastrKeys,
                        ),
                        onRemove: (it) =>
                            _removeItem(_kadastrItems, it, _syncKadastrKeys),
                        onPreview: (it) => _openPreview(_kadastrItems, it),
                      ),
                      const SizedBox(height: 20),
                      _FloorSection(
                        floorCtrl: _floorCtrl,
                        totalFloorsCtrl: _totalFloorsCtrl,
                        onFloorChanged: _setFloor,
                        onTotalChanged: _setTotalFloors,
                      ),
                      const SizedBox(height: 20),
                      _RoomsSelector(
                        rooms: b.rooms,
                        onChanged: () => setState(() {}),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  // No permanent "X required" banner — the button stays disabled
                  // and tapping it surfaces what's missing as a toast (same UX
                  // as AI Baholash). Quiet by default, guidance on demand.
                  child: _buildSubmit(l),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Per-file upload state ─────────────────────────────────────────────
enum _UpStatus { uploading, done, failed }

class _UploadItem {
  _UploadItem(this.path);

  final String path;
  _UpStatus status = _UpStatus.uploading;
  String? key; // server object key once uploaded
  String? error; // failure reason (drives the retry overlay)

  static const Set<String> _imageExts = {
    'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp',
  };

  static String extOf(String path) {
    final name = path.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : '';
  }

  static bool isImagePath(String path) => _imageExts.contains(extOf(path));
  bool get isImage => isImagePath(path);
}

// ── Upload card ───────────────────────────────────────────────────────
// Header (icon / title / hint + done-count badge) over a grid of per-file
// tiles. Each tile uploads + retries on its own; a trailing "+" tile adds more
// (so only the "+" is a tap target, never the whole card).
class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.title,
    required this.hint,
    required this.icon,
    required this.emptyIcon,
    required this.actionLabel,
    required this.items,
    required this.maxFiles,
    required this.onAdd,
    required this.onRetry,
    required this.onRemove,
    required this.onPreview,
  });

  final String title;
  final String hint;
  final IconData icon;
  final IconData emptyIcon;
  final String actionLabel;
  final List<_UploadItem> items;
  final int maxFiles;
  final VoidCallback onAdd;
  final ValueChanged<_UploadItem> onRetry;
  final ValueChanged<_UploadItem> onRemove;
  final ValueChanged<_UploadItem> onPreview;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    final doneCount = items.where((i) => i.status == _UpStatus.done).length;
    final canAdd = items.length < maxFiles;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 26, color: AppColors.splashGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: textColor,
                            ),
                          ),
                        ),
                        if (doneCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.splashGreen.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$doneCount',
                              style: const TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.splashGreen,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontSize: 12,
                        height: 1.3,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            // First upload: a full-width, inviting drop zone (not a tiny square).
            _EmptyDropZone(label: actionLabel, icon: emptyIcon, onTap: onAdd)
          else
            // Once a file exists: one horizontal swipeable row, "+" pinned first.
            SizedBox(
              height: _UploadTile.outerSize,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  if (canAdd) ...[
                    _AddTile(onTap: onAdd),
                    const SizedBox(width: 8),
                  ],
                  for (int i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _UploadTile(
                      item: items[i],
                      onRetry: () => onRetry(items[i]),
                      onRemove: () => onRemove(items[i]),
                      onPreview: () => onPreview(items[i]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── One file tile ─────────────────────────────────────────────────────
// Thumbnail (image) or file-type chip, with a per-file status overlay: a
// spinner while uploading, a tap-to-retry overlay on failure, a check when
// done. The × badge removes it; tapping a finished image opens the gallery.
class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.item,
    required this.onRetry,
    required this.onRemove,
    required this.onPreview,
  });

  final _UploadItem item;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  static const double _size = 76;
  static const double outerSize = _size + 6;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBg = isDark ? const Color(0xFF14181A) : const Color(0xFFF1F2F4);
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    Widget base;
    if (item.isImage) {
      base = Image.file(
        File(item.path),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: chipBg,
          child: Icon(Icons.broken_image_outlined, size: 22, color: muted),
        ),
      );
    } else {
      final ext = _UploadItem.extOf(item.path).toUpperCase();
      base = Container(
        color: chipBg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 24, color: muted),
            const SizedBox(height: 4),
            Text(
              ext.isEmpty ? tr(l, 'services.k3d.intake.file') : ext,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 9.5,
                color: muted,
              ),
            ),
          ],
        ),
      );
    }

    final tappable = item.status == _UpStatus.done && item.isImage;

    return SizedBox(
      width: _size + 6,
      height: _size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: _size,
                height: _size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: GestureDetector(
                        onTap: tappable ? onPreview : null,
                        child: base,
                      ),
                    ),
                    if (item.status == _UpStatus.uploading)
                      Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    else if (item.status == _UpStatus.failed)
                      Tooltip(
                        message: item.error ?? '',
                        triggerMode: TooltipTriggerMode.longPress,
                        child: GestureDetector(
                          onTap: onRetry,
                          child: Container(
                            color: const Color(
                              0xFFE5484D,
                            ).withValues(alpha: 0.62),
                            child: const Center(
                              child: Icon(
                                Icons.refresh_rounded,
                                size: 26,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Remove (×) — always present, so a stuck/failed file can be cleared.
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF14181A) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: border),
                ),
                child: Icon(Icons.close_rounded, size: 13, color: muted),
              ),
            ),
          ),
          if (item.status == _UpStatus.done)
            Positioned(
              left: 3,
              bottom: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: AppColors.splashGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── "Add file" tile (the +) ───────────────────────────────────────────
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;
  static const double _size = 76;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF14181A) : const Color(0xFFF7F8F9);

    // Match _UploadTile geometry exactly (76 square offset 6px from top) so the
    // "+" lines up with the thumbnails in the swipeable row.
    return SizedBox(
      width: _size + 6,
      height: _size + 6,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            width: _size,
            height: _size,
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.splashGreen.withValues(alpha: 0.5),
                      width: 1.4,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_rounded,
                      size: 28,
                      color: AppColors.splashGreen,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── First-upload drop zone ────────────────────────────────────────────
// Full-width, dashed, tappable. Shown only while a category has zero files;
// the compact _AddTile takes over once the first file lands.
class _EmptyDropZone extends StatelessWidget {
  const _EmptyDropZone({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.splashGreen;
    final fill = accent.withValues(alpha: isDark ? 0.07 : 0.05);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return SizedBox(
      width: double.infinity,
      height: 108,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: CustomPaint(
          painter: _DashedRRectPainter(
            color: accent.withValues(alpha: 0.55),
            radius: 14,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 24, color: accent),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dashed rounded-rectangle border (no extra dependency) ─────────────
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, this.radius = 14});

  final Color color;
  final double radius;

  static const double _dash = 6;
  static const double _gap = 5;
  static const double _strokeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;
    const inset = _strokeWidth / 2;
    final source = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - _strokeWidth,
            size.height - _strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + _dash, metric.length);
        dashed.addPath(metric.extractPath(dist, next), Offset.zero);
        dist += _dash + _gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Floor section ─────────────────────────────────────────────────────
class _FloorSection extends StatelessWidget {
  const _FloorSection({
    required this.floorCtrl,
    required this.totalFloorsCtrl,
    required this.onFloorChanged,
    required this.onTotalChanged,
  });

  final TextEditingController floorCtrl;
  final TextEditingController totalFloorsCtrl;
  final ValueChanged<String> onFloorChanged;
  final ValueChanged<String> onTotalChanged;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(l, 'services.k3d.intake.floor'),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          tr(l, 'services.k3d.intake.floor_description'),
          style: TextStyle(fontFamily: 'MTSCompact', fontSize: 12, color: muted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FloorField(
                label: tr(l, 'services.k3d.intake.object_floor'),
                controller: floorCtrl,
                onChanged: onFloorChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FloorField(
                label: tr(l, 'services.k3d.intake.total_floors'),
                controller: totalFloorsCtrl,
                onChanged: onTotalChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FloorField extends StatelessWidget {
  const _FloorField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1F2426) : const Color(0xFFF7F8F9);
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Container(
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 11,
              color: muted,
            ),
          ),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            onChanged: onChanged,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: textColor,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '—',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rooms selector ────────────────────────────────────────────────────
class _RoomsSelector extends StatefulWidget {
  const _RoomsSelector({required this.rooms, this.onChanged});

  final List<AiRoom> rooms;
  final VoidCallback? onChanged;

  @override
  State<_RoomsSelector> createState() => _RoomsSelectorState();
}

class _RoomsSelectorState extends State<_RoomsSelector> {
  static final List<RoomKind> _standardKinds =
      RoomKind.values.where((k) => k != RoomKind.other).toList();

  final Map<AiRoom, TextEditingController> _counts = {};
  final TextEditingController _customName = TextEditingController();
  bool _customOpen = false;

  @override
  void initState() {
    super.initState();
    for (final r in widget.rooms) {
      _counts[r] = TextEditingController(text: '${r.count}');
    }
    _customOpen = widget.rooms.any((r) => r.kind == RoomKind.other);
  }

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    _customName.dispose();
    super.dispose();
  }

  AiRoom? _standardRoom(RoomKind k) {
    for (final r in widget.rooms) {
      if (r.kind == k && k != RoomKind.other) return r;
    }
    return null;
  }

  void _toggleStandard(RoomKind k) {
    HapticFeedback.selectionClick();
    final existing = _standardRoom(k);
    setState(() {
      if (existing != null) {
        widget.rooms.remove(existing);
        _counts.remove(existing)?.dispose();
      } else {
        final room = AiRoom(kind: k, count: 1);
        widget.rooms.add(room);
        _counts[room] = TextEditingController(text: '1');
      }
    });
    widget.onChanged?.call();
  }

  void _addCustom() {
    final name = _customName.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      final room = AiRoom(kind: RoomKind.other, name: name, count: 1);
      widget.rooms.add(room);
      _counts[room] = TextEditingController(text: '1');
      _customName.clear();
    });
    widget.onChanged?.call();
  }

  void _remove(AiRoom room) {
    setState(() {
      widget.rooms.remove(room);
      _counts.remove(room)?.dispose();
    });
    widget.onChanged?.call();
  }

  void _setCount(AiRoom room, int value) {
    final v = value.clamp(1, 50);
    room.count = v;
    final ctrl = _counts[room];
    if (ctrl != null && ctrl.text != '$v') {
      ctrl.text = '$v';
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    final selectedKinds = widget.rooms.map((r) => r.kind).toSet();
    final hasCustom = widget.rooms.any((r) => r.kind == RoomKind.other);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(l, 'services.k3d.intake.rooms'),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          tr(l, 'services.k3d.intake.rooms_hint'),
          style: TextStyle(fontFamily: 'MTSCompact', fontSize: 12, color: muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in _standardKinds)
              _RoomChip(
                label: k.label(l),
                selected: selectedKinds.contains(k),
                onTap: () => _toggleStandard(k),
              ),
            _RoomChip(
              label: RoomKind.other.label(l),
              selected: _customOpen || hasCustom,
              onTap: () => setState(() => _customOpen = !_customOpen),
            ),
          ],
        ),
        if (_customOpen) ...[
          const SizedBox(height: 12),
          _CustomNameInput(
            controller: _customName,
            onAdd: _addCustom,
          ),
        ],
        if (widget.rooms.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final room in widget.rooms)
            _RoomCountRow(
              label: room.kind == RoomKind.other
                  ? (room.name?.trim().isNotEmpty ?? false
                      ? room.name!.trim()
                      : RoomKind.other.label(l))
                  : room.kind.label(l),
              controller: _counts[room]!,
              count: room.count,
              onMinus: () => room.count <= 1
                  ? _remove(room)
                  : _setCount(room, room.count - 1),
              onPlus: () => _setCount(room, room.count + 1),
              onTyped: (txt) {
                final n = int.tryParse(txt);
                if (n != null) _setCount(room, n);
              },
            ),
        ],
      ],
    );
  }
}

class _CustomNameInput extends StatelessWidget {
  const _CustomNameInput({required this.controller, required this.onAdd});
  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1F2426) : const Color(0xFFF7F8F9);
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.only(left: 14, right: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onAdd(),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontSize: 15,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: tr(locale, 'services.k3d.intake.custom_room_hint'),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle, size: 30),
            color: AppColors.splashGreen,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idleBg = isDark ? const Color(0xFF1F2426) : const Color(0xFFF1F2F4);
    final idleText = isDark ? Colors.white : AppColors.textBlack;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);

    return Material(
      color: selected
          ? AppColors.splashGreen.withValues(alpha: 0.16)
          : idleBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.splashGreen : border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, size: 15, color: AppColors.splashGreen),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: selected ? AppColors.splashGreen : idleText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCountRow extends StatelessWidget {
  const _RoomCountRow({
    required this.label,
    required this.controller,
    required this.count,
    required this.onMinus,
    required this.onPlus,
    required this.onTyped,
  });

  final String label;
  final TextEditingController controller;
  final int count;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<String> onTyped;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    final atOne = count <= 1;
    final minusColor = atOne ? const Color(0xFFE5484D) : AppColors.splashGreen;
    final minusIcon = atOne ? Icons.close_rounded : Icons.remove_rounded;

    Widget stepBtn(IconData icon, VoidCallback onTap, Color color) => InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 20, color: color),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: textColor,
              ),
            ),
          ),
          stepBtn(minusIcon, onMinus, minusColor),
          SizedBox(
            width: 34,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              onChanged: onTyped,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: textColor,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
              ),
            ),
          ),
          stepBtn(Icons.add_rounded, onPlus, AppColors.splashGreen),
        ],
      ),
    );
  }
}

