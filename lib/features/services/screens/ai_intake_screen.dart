/// AI Baholash wizard — intake step.
///
/// One scrollable screen with four sections:
///   • Property photos (inside/outside, 1-15)  → vision condition
///   • Kadastr documents (1-20)                → AI fact extraction
///   • Passport / ID (optional)                → owner for the report
///   • Rooms (optional)                        → dynamic breakdown
///
/// Files are uploaded to S3 the moment they're picked; the returned keys are
/// stored on the bundle. Photos, kadastr documents, and the floor numbers are
/// required to enable "Hisoblash"; passport and rooms are optional. Tapping the
/// still-disabled button surfaces what's missing (no permanent banner).
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../auth/widgets/auth_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../ai_draft_saver.dart';
import '../api_ai_upload_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/file_preview_gallery.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_review_screen.dart';

class AiIntakeScreen extends StatefulWidget {
  const AiIntakeScreen({super.key, required this.bundle});

  final AiBaholashBundle bundle;

  @override
  State<AiIntakeScreen> createState() => _AiIntakeScreenState();
}

class _AiIntakeScreenState extends State<AiIntakeScreen> {
  final AiUploadService _uploads = AiUploadService();
  final ImagePicker _imagePicker = ImagePicker();

  // Per-FILE upload state (ChatGPT-style): each picked file is its own tile that
  // uploads independently and can be retried / removed on its own. The bundle's
  // server-key lists are kept in sync with the items that finished uploading.
  final List<_UploadItem> _photoItems = [];
  final List<_UploadItem> _kadastrItems = [];
  final List<_UploadItem> _passportItems = [];

  bool get _anyUploading =>
      _photoItems.any((i) => i.status == _UpStatus.uploading) ||
      _kadastrItems.any((i) => i.status == _UpStatus.uploading) ||
      _passportItems.any((i) => i.status == _UpStatus.uploading);

  // Floor inputs — required. Mirror straight into the bundle on change.
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
    _rehydrate(
      _passportItems,
      widget.bundle.passportPaths,
      widget.bundle.passportKeys,
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

  // Backend caps total_floors at 200 (le=200). Validate client-side so the
  // user gets a friendly hint instead of a raw 422 from the server.
  static const int _maxFloors = 200;

  // ── Required-fields gate ──────────────────────────────────────────────
  // Photos, kadastr docs, rooms, and both floor numbers are mandatory.
  // Passport stays optional.
  bool get _ready =>
      !_anyUploading &&
      widget.bundle.imageKeys.isNotEmpty &&
      widget.bundle.kadastrKeys.isNotEmpty &&
      widget.bundle.floor != null &&
      widget.bundle.totalFloors != null &&
      widget.bundle.floor! >= 1 &&
      widget.bundle.totalFloors! >= 1 &&
      widget.bundle.totalFloors! <= _maxFloors &&
      widget.bundle.floor! <= widget.bundle.totalFloors!;

  // Short hint listing what's still missing, or null when ready.
  String? get _missingHint {
    if (_ready) return null;
    final l = localeNotifier.value;
    if (_anyUploading) return _Strings.uploadingFiles(l);
    final missing = <String>[];
    if (widget.bundle.imageKeys.isEmpty) missing.add(_Strings.missingPhoto(l));
    if (widget.bundle.kadastrKeys.isEmpty) {
      missing.add(_Strings.missingKadastr(l));
    }
    final f = widget.bundle.floor;
    final tf = widget.bundle.totalFloors;
    if (f == null || tf == null || f < 1 || tf < 1) {
      missing.add(_Strings.missingFloor(l));
    } else if (tf > _maxFloors) {
      return _Strings.floorMax(l, _maxFloors);
    } else if (f > tf) {
      return _Strings.floorExceeds(l);
    }
    return _Strings.requiredSuffix(l, missing.join(', '));
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
      _toast(_Strings.maxPhotos(localeNotifier.value, 15));
      return;
    }
    final List<XFile> picked = await _imagePicker.pickMultiImage(
      limit: remaining,
    );
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

  // ── Passport (file_picker, optional) ────────────────────────────────
  Future<void> _addPassport() => _pickDocs(
    category: UploadCategory.passport,
    items: _passportItems,
    maxTotal: 5,
    sync: _syncPassportKeys,
  );

  Future<void> _pickDocs({
    required UploadCategory category,
    required List<_UploadItem> items,
    required int maxTotal,
    required VoidCallback sync,
  }) async {
    final remaining = maxTotal - items.length;
    if (remaining <= 0) {
      _toast(_Strings.maxFiles(localeNotifier.value, maxTotal));
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'jpg',
        'jpeg',
        'png',
        'webp',
        'heic',
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
        item.error = _Strings.authRequired(localeNotifier.value);
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
      );
      if (!mounted) return;
      setState(() {
        item.key = keys.isNotEmpty ? keys.first : null;
        item.status = item.key != null ? _UpStatus.done : _UpStatus.failed;
        if (item.key == null) {
          item.error = _Strings.uploadFailed(localeNotifier.value);
        }
      });
    } on AiUploadException catch (e) {
      if (!mounted) return;
      // 400 = backend rejected this file (too big / wrong type / over the cap).
      setState(() {
        item.status = _UpStatus.failed;
        item.error = e.statusCode == 400
            ? _Strings.uploadRejected(localeNotifier.value)
            : _Strings.uploadFailed(localeNotifier.value);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        item.status = _UpStatus.failed;
        item.error = _Strings.uploadFailed(localeNotifier.value);
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
  void _syncPassportKeys() => _sync(
    _passportItems,
    widget.bundle.passportKeys,
    widget.bundle.passportPaths,
  );

  // Rebuild the bundle's server-key list AND the index-aligned local-path list
  // from the items that finished uploading — so the review step can show
  // thumbnails and a re-entered intake can restore its tiles.
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

  // ── Submit ──────────────────────────────────────────────────────────
  // Surfaces what's still required — but only when the user actually taps the
  // (disabled) Hisoblash, instead of a permanent amber banner nagging the whole
  // time. Quiet by default, guidance on demand.
  void _showMissing() {
    final msg = _missingHint;
    if (msg != null) _toast(msg);
  }

  // The submit button. When the form isn't ready it stays visually disabled,
  // but a transparent tap layer reveals the missing items via a toast.
  Widget _buildSubmit(Locale l) {
    final button = ListingCtaButton(
      label: _Strings.continueLabel(l),
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

  // Intake hands off to the review step (which then submits). Save the draft
  // first so the draft/resume flow keeps working.
  Future<void> _continue() async {
    HapticFeedback.lightImpact();
    await saveAiDraftStep(widget.bundle, 'payment'); // oxirgi qadam: to'lov
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/review'),
        builder: (_) => AiReviewScreen(bundle: widget.bundle),
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
                    title: _Strings.appBarTitle(l),
                    subtitle: _Strings.appBarSubtitle(l),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(count: 8, activeIndex: 5),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _UploadCard(
                        title: _Strings.objectPhotos(l),
                        hint: _Strings.objectPhotosHint(l),
                        icon: Icons.photo_camera_outlined,
                        emptyIcon: Icons.add_photo_alternate_outlined,
                        actionLabel: _Strings.addPhotosCta(l),
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
                        title: _Strings.kadastrDocs(l),
                        hint: _Strings.kadastrDocsHint(l),
                        icon: Icons.description_outlined,
                        emptyIcon: Icons.upload_file_outlined,
                        actionLabel: _Strings.addDocsCta(l),
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
                      const SizedBox(height: 12),
                      _UploadCard(
                        title: _Strings.passport(l),
                        hint: _Strings.passportHint(l),
                        icon: Icons.badge_outlined,
                        emptyIcon: Icons.upload_file_outlined,
                        actionLabel: _Strings.addFilesCta(l),
                        items: _passportItems,
                        maxFiles: 5,
                        onAdd: _addPassport,
                        onRetry: (it) => _retry(
                          it,
                          UploadCategory.passport,
                          _syncPassportKeys,
                        ),
                        onRemove: (it) =>
                            _removeItem(_passportItems, it, _syncPassportKeys),
                        onPreview: (it) => _openPreview(_passportItems, it),
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
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'gif',
    'bmp',
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
              ext.isEmpty ? _Strings.file(l) : ext,
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

// (full-screen preview gallery moved to widgets/file_preview_gallery.dart)

// ── Floor section ─────────────────────────────────────────────────────
// Two required number fields: which floor the object sits on, and how many
// floors the building has. Both feed the backend's floor-position price
// adjustment.
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
          _Strings.floor(l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _Strings.floorDescription(l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 12,
            color: muted,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FloorField(
                label: _Strings.objectFloor(l),
                controller: floorCtrl,
                onChanged: onFloorChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FloorField(
                label: _Strings.totalFloors(l),
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
// Chips shown inline under the title. Tap a chip to (de)select a room type;
// each selected type gets its own row below with a typeable count + stepper.
class _RoomsSelector extends StatefulWidget {
  const _RoomsSelector({required this.rooms, this.onChanged});

  /// The bundle's room list — mutated in place as the user selects/edits.
  final List<AiRoom> rooms;

  /// Fired after any add/remove so the parent can re-evaluate the submit gate.
  final VoidCallback? onChanged;

  @override
  State<_RoomsSelector> createState() => _RoomsSelectorState();
}

class _RoomsSelectorState extends State<_RoomsSelector> {
  // Standard room kinds shown as toggle chips (everything except `other`).
  static final List<RoomKind> _standardKinds = RoomKind.values
      .where((k) => k != RoomKind.other)
      .toList();

  // One count-controller per room *instance* (so multiple custom rooms with
  // different names each get their own field).
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
          _Strings.roomsOptional(l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _Strings.roomsHint(l),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 12,
            color: muted,
          ),
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
            // "Boshqa" opens a custom-name input instead of adding a fixed row.
            _RoomChip(
              label: RoomKind.other.label(l),
              selected: _customOpen || hasCustom,
              onTap: () => setState(() => _customOpen = !_customOpen),
            ),
          ],
        ),
        if (_customOpen) ...[
          const SizedBox(height: 12),
          _CustomNameInput(controller: _customName, onAdd: _addCustom),
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
              // Minus at 1 removes the room (toggles it off); otherwise -1.
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

// Inline "add custom room" field — text + a green add button.
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
                hintText: switch (locale.languageCode) {
                  'ru' => 'Название комнаты (например: Кабинет)',
                  'en' => 'Room name (e.g. Office)',
                  _ => 'Xona nomi (masalan: Ish xonasi)',
                },
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
      color: selected ? AppColors.splashGreen.withValues(alpha: 0.16) : idleBg,
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
  // onMinus removes the room when count == 1 (toggle off), else decrements.
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<String> onTyped;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    // At count 1 the minus turns into a "remove" affordance (red-ish) so it
    // reads as "tap again to deselect", per the toggle behaviour.
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

// ── Localized strings ─────────────────────────────────────────────────
class _Strings {
  const _Strings._();

  static String appBarTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Документы и фото',
    'en' => 'Documents and photos',
    _ => 'Hujjat va rasmlar',
  };

  static String appBarSubtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Необходимые данные для оценки',
    'en' => 'Data required for valuation',
    _ => 'Baholash uchun zarur ma\'lumotlar',
  };

  static String continueLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Продолжить',
    'en' => 'Continue',
    _ => 'Davom etish',
  };

  static String objectPhotos(Locale l) => switch (l.languageCode) {
    'ru' => 'Фото объекта',
    'en' => 'Object photos',
    _ => 'Obyekt rasmlari',
  };

  static String objectPhotosHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Внутри и снаружи (1-15). Для оценки состояния.',
    'en' => 'Inside and outside (1-15). To assess the condition.',
    _ => 'Ichki va tashqi (1-15). Holatni baholash uchun.',
  };

  static String kadastrDocs(Locale l) => switch (l.languageCode) {
    'ru' => 'Кадастровые документы',
    'en' => 'Cadastre documents',
    _ => 'Kadastr hujjatlari',
  };

  static String kadastrDocsHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Техпаспорт, план (1-20). Определяются площадь/год.',
    'en' => 'Tech passport, plan (1-20). Area/year are determined.',
    _ => 'Texpasport, plan (1-20). Maydon/yil aniqlanadi.',
  };

  static String passport(Locale l) => switch (l.languageCode) {
    'ru' => 'Паспорт / ID (необязательно)',
    'en' => 'Passport / ID (optional)',
    _ => 'Pasport / ID (ixtiyoriy)',
  };

  static String passportHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Данные владельца для отчёта.',
    'en' => 'Owner\'s data for the report.',
    _ => 'Hisobot uchun egasining ma\'lumoti.',
  };

  static String floor(Locale l) => switch (l.languageCode) {
    'ru' => 'Этаж',
    'en' => 'Floor',
    _ => 'Qavat',
  };

  static String floorDescription(Locale l) => switch (l.languageCode) {
    'ru' => 'Этаж объекта и всего этажей в здании',
    'en' => 'Object floor and total floors in the building',
    _ => 'Obyekt qavati va binodagi jami qavatlar',
  };

  static String objectFloor(Locale l) => switch (l.languageCode) {
    'ru' => 'Этаж объекта',
    'en' => 'Object floor',
    _ => 'Obyekt qavati',
  };

  static String totalFloors(Locale l) => switch (l.languageCode) {
    'ru' => 'Всего этажей',
    'en' => 'Total floors',
    _ => 'Jami qavatlar',
  };

  static String roomsOptional(Locale l) => switch (l.languageCode) {
    'ru' => 'Комнаты (необязательно)',
    'en' => 'Rooms (optional)',
    _ => 'Xonalar (ixtiyoriy)',
  };

  static String roomsHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Выберите типы комнат, укажите количество',
    'en' => 'Select room types, enter the count',
    _ => 'Xona turlarini tanlang, sonini kiriting',
  };

  static String file(Locale l) => switch (l.languageCode) {
    'ru' => 'файл',
    'en' => 'file',
    _ => 'fayl',
  };

  static String maxPhotos(Locale l, int n) => switch (l.languageCode) {
    'ru' => 'Не более $n фото',
    'en' => 'Up to $n photos',
    _ => 'Ko\'pi bilan $n ta rasm',
  };

  static String maxFiles(Locale l, int n) => switch (l.languageCode) {
    'ru' => 'Не более $n файлов',
    'en' => 'Up to $n files',
    _ => 'Ko\'pi bilan $n ta fayl',
  };

  static String authRequired(Locale l) => switch (l.languageCode) {
    'ru' => 'Требуется авторизация',
    'en' => 'Authorization required',
    _ => 'Avtorizatsiya kerak',
  };

  static String uploadingFiles(Locale l) => switch (l.languageCode) {
    'ru' => 'Файлы загружаются…',
    'en' => 'Uploading files…',
    _ => 'Fayllar yuklanmoqda…',
  };

  static String uploadFailed(Locale l) => switch (l.languageCode) {
    'ru' => 'Не загрузилось — нажмите, чтобы повторить',
    'en' => 'Upload failed — tap to retry',
    _ => 'Yuklanmadi — qayta urinish uchun bosing',
  };

  static String uploadRejected(Locale l) => switch (l.languageCode) {
    'ru' => 'Файл отклонён (тип/размер) — нажмите для повтора',
    'en' => 'File rejected (type/size) — tap to retry',
    _ => 'Fayl rad etildi (tur/hajm) — qayta bosing',
  };

  static String addPhotosCta(Locale l) => switch (l.languageCode) {
    'ru' => 'Добавить фото',
    'en' => 'Add photos',
    _ => 'Rasm qo\'shish',
  };

  static String addDocsCta(Locale l) => switch (l.languageCode) {
    'ru' => 'Добавить документ',
    'en' => 'Add document',
    _ => 'Hujjat qo\'shish',
  };

  static String addFilesCta(Locale l) => switch (l.languageCode) {
    'ru' => 'Добавить файл',
    'en' => 'Add file',
    _ => 'Fayl qo\'shish',
  };

  static String missingPhoto(Locale l) => switch (l.languageCode) {
    'ru' => 'фото',
    'en' => 'photo',
    _ => 'rasm',
  };

  static String missingKadastr(Locale l) => switch (l.languageCode) {
    'ru' => 'кадастровый документ',
    'en' => 'cadastre document',
    _ => 'kadastr hujjati',
  };

  static String missingFloor(Locale l) => switch (l.languageCode) {
    'ru' => 'этаж',
    'en' => 'floor',
    _ => 'qavat',
  };

  static String floorExceeds(Locale l) => switch (l.languageCode) {
    'ru' => 'Этаж не может быть больше общего числа этажей',
    'en' => 'The floor cannot exceed the total number of floors',
    _ => 'Qavat binodagi jami qavatlardan katta bo\'lmasligi kerak',
  };

  static String floorMax(Locale l, int max) => switch (l.languageCode) {
    'ru' => 'Всего этажей не может превышать $max',
    'en' => 'Total floors cannot exceed $max',
    _ => 'Jami qavatlar $max dan oshmasligi kerak',
  };

  static String requiredSuffix(Locale l, String items) =>
      switch (l.languageCode) {
        'ru' => '$items — обязательно',
        'en' => '$items required',
        _ => '$items majburiy',
      };
}
