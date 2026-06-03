/// AI Baholash wizard — intake step.
///
/// One scrollable screen with four sections:
///   • Property photos (inside/outside, 1-15)  → vision condition
///   • Kadastr documents (1-20)                → AI fact extraction
///   • Passport / ID (optional)                → owner for the report
///   • Rooms (optional)                        → dynamic breakdown
///
/// Files are uploaded to S3 the moment they're picked; the returned keys are
/// stored on the bundle. Nothing here is required — the user can go straight
/// to "Hisoblash" and the backend handles missing inputs with sane defaults.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../api_ai_upload_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/rooms_selector.dart';
import '../widgets/service_app_bar.dart';
import 'ai_status_screen.dart';

class AiIntakeScreen extends StatefulWidget {
  const AiIntakeScreen({super.key, required this.bundle});

  final AiBaholashBundle bundle;

  @override
  State<AiIntakeScreen> createState() => _AiIntakeScreenState();
}

class _AiIntakeScreenState extends State<AiIntakeScreen> {
  final AiUploadService _uploads = AiUploadService();
  final ImagePicker _imagePicker = ImagePicker();

  // Per-section busy flags so each card shows its own spinner.
  bool _photosBusy = false;
  bool _kadastrBusy = false;
  bool _passportBusy = false;
  bool _submitting = false;

  // Local file paths for the picked files, index-aligned with the bundle's
  // key lists. The keys are server-side and can't be rendered directly, so we
  // keep the on-device path to draw a thumbnail / file chip. Removing index i
  // drops both the path here and the key on the bundle.
  final List<String> _photoPaths = [];
  final List<String> _kadastrPaths = [];
  final List<String> _passportPaths = [];

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
  }

  @override
  void dispose() {
    _uploads.dispose();
    _floorCtrl.dispose();
    _totalFloorsCtrl.dispose();
    super.dispose();
  }

  // ── Required-fields gate ──────────────────────────────────────────────
  // Photos, kadastr docs, rooms, and both floor numbers are mandatory.
  // Passport stays optional.
  bool get _ready =>
      widget.bundle.imageKeys.isNotEmpty &&
      widget.bundle.kadastrKeys.isNotEmpty &&
      widget.bundle.rooms.isNotEmpty &&
      widget.bundle.floor != null &&
      widget.bundle.totalFloors != null &&
      widget.bundle.floor! >= 1 &&
      widget.bundle.totalFloors! >= 1 &&
      widget.bundle.floor! <= widget.bundle.totalFloors!;

  // Short hint listing what's still missing, or null when ready.
  String? _missingHint(Locale l) {
    if (_ready) return null;
    final missing = <String>[];
    if (widget.bundle.imageKeys.isEmpty) {
      missing.add(_IntakeStrings.missingPhoto(l));
    }
    if (widget.bundle.kadastrKeys.isEmpty) {
      missing.add(_IntakeStrings.missingKadastr(l));
    }
    if (widget.bundle.rooms.isEmpty) {
      missing.add(_IntakeStrings.missingRooms(l));
    }
    final f = widget.bundle.floor;
    final tf = widget.bundle.totalFloors;
    if (f == null || tf == null || f < 1 || tf < 1) {
      missing.add(_IntakeStrings.missingFloor(l));
    } else if (f > tf) {
      return _IntakeStrings.floorTooHigh(l);
    }
    return _IntakeStrings.missingRequired(l, missing.join(', '));
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Property photos (image_picker) ──────────────────────────────────
  Future<void> _addPhotos() async {
    final remaining = 15 - widget.bundle.imageKeys.length;
    if (remaining <= 0) {
      _snack(_IntakeStrings.maxPhotos(Localizations.localeOf(context)));
      return;
    }
    final List<XFile> picked = await _imagePicker.pickMultiImage(limit: remaining);
    if (picked.isEmpty) return;
    await _doUpload(
      category: UploadCategory.propertyPhoto,
      paths: picked.map((x) => x.path).toList(),
      target: widget.bundle.imageKeys,
      targetPaths: _photoPaths,
      setBusy: (v) => setState(() => _photosBusy = v),
    );
  }

  // ── Kadastr docs (file_picker: images + pdf) ────────────────────────
  Future<void> _addKadastr() async {
    await _pickFilesUpload(
      category: UploadCategory.kadastr,
      target: widget.bundle.kadastrKeys,
      targetPaths: _kadastrPaths,
      maxTotal: 20,
      setBusy: (v) => setState(() => _kadastrBusy = v),
    );
  }

  // ── Passport (file_picker, optional) ────────────────────────────────
  Future<void> _addPassport() async {
    await _pickFilesUpload(
      category: UploadCategory.passport,
      target: widget.bundle.passportKeys,
      targetPaths: _passportPaths,
      maxTotal: 5,
      setBusy: (v) => setState(() => _passportBusy = v),
    );
  }

  // Drop the file at index `i` from a section — both its on-device path and
  // its server-side key stay aligned.
  void _removeAt(List<String> target, List<String> targetPaths, int i) {
    HapticFeedback.lightImpact();
    setState(() {
      if (i >= 0 && i < target.length) target.removeAt(i);
      if (i >= 0 && i < targetPaths.length) targetPaths.removeAt(i);
    });
  }

  Future<void> _pickFilesUpload({
    required UploadCategory category,
    required List<String> target,
    required List<String> targetPaths,
    required int maxTotal,
    required void Function(bool) setBusy,
  }) async {
    final remaining = maxTotal - target.length;
    if (remaining <= 0) {
      _snack(_IntakeStrings.maxFiles(
          Localizations.localeOf(context), maxTotal));
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
    await _doUpload(
      category: category,
      paths: paths,
      target: target,
      targetPaths: targetPaths,
      setBusy: setBusy,
    );
  }

  Future<void> _doUpload({
    required UploadCategory category,
    required List<String> paths,
    required List<String> target,
    required List<String> targetPaths,
    required void Function(bool) setBusy,
  }) async {
    if (paths.isEmpty) return;
    final token = await _token();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      _snack(_IntakeStrings.authRequired(Localizations.localeOf(context)));
      return;
    }
    setBusy(true);
    try {
      final keys = await _uploads.upload(
        category: category, filePaths: paths, token: token);
      if (!mounted) return;
      // keys come back 1:1 and in order with `paths`; keep the previews aligned
      // to whatever actually uploaded.
      setState(() {
        target.addAll(keys);
        targetPaths.addAll(paths.take(keys.length));
      });
    } catch (e) {
      if (mounted) {
        _snack(_IntakeStrings.uploadError(
            Localizations.localeOf(context), '$e'));
      }
    } finally {
      if (mounted) setBusy(false);
    }
  }

  // ── Submit ──────────────────────────────────────────────────────────
  void _calculate() {
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiStatusScreen(bundle: widget.bundle),
      ),
    ).then((_) {
      if (mounted) setState(() => _submitting = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final b = widget.bundle;
    final missingHint = _missingHint(l);

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
                    title: _IntakeStrings.title(l),
                    subtitle: _IntakeStrings.subtitle(l),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _UploadCard(
                        title: _IntakeStrings.photosTitle(l),
                        hint: _IntakeStrings.photosHint(l),
                        icon: Icons.photo_camera_outlined,
                        count: b.imageKeys.length,
                        busy: _photosBusy,
                        onAdd: _addPhotos,
                        paths: _photoPaths,
                        onRemove: (i) =>
                            _removeAt(b.imageKeys, _photoPaths, i),
                      ),
                      const SizedBox(height: 12),
                      _UploadCard(
                        title: _IntakeStrings.kadastrTitle(l),
                        hint: _IntakeStrings.kadastrHint(l),
                        icon: Icons.description_outlined,
                        count: b.kadastrKeys.length,
                        busy: _kadastrBusy,
                        onAdd: _addKadastr,
                        paths: _kadastrPaths,
                        onRemove: (i) =>
                            _removeAt(b.kadastrKeys, _kadastrPaths, i),
                      ),
                      const SizedBox(height: 12),
                      _UploadCard(
                        title: _IntakeStrings.passportTitle(l),
                        hint: _IntakeStrings.passportHint(l),
                        icon: Icons.badge_outlined,
                        count: b.passportKeys.length,
                        busy: _passportBusy,
                        onAdd: _addPassport,
                        paths: _passportPaths,
                        onRemove: (i) =>
                            _removeAt(b.passportKeys, _passportPaths, i),
                      ),
                      const SizedBox(height: 20),
                      _FloorSection(
                        floorCtrl: _floorCtrl,
                        totalFloorsCtrl: _totalFloorsCtrl,
                        onFloorChanged: _setFloor,
                        onTotalChanged: _setTotalFloors,
                        locale: l,
                      ),
                      const SizedBox(height: 20),
                      RoomsSelector(
                        rooms: b.rooms,
                        onChanged: () => setState(() {}),
                        locale: l,
                        title: _IntakeStrings.roomsTitle(l),
                        subtitle: _IntakeStrings.roomsSubtitle(l),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (missingHint != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 15, color: Color(0xFFE5A23D)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  missingHint,
                                  style: const TextStyle(
                                    fontFamily: 'MTSText',
                                    fontSize: 12,
                                    color: Color(0xFFE5A23D),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      ListingCtaButton(
                        label: _submitting
                            ? _IntakeStrings.submitting(l)
                            : _IntakeStrings.calculate(l),
                        enabled: _ready && !_submitting,
                        onTap: _calculate,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Upload card ───────────────────────────────────────────────────────
class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.title,
    required this.hint,
    required this.icon,
    required this.count,
    required this.busy,
    required this.onAdd,
    required this.paths,
    required this.onRemove,
  });

  final String title;
  final String hint;
  final IconData icon;
  final int count;
  final bool busy;
  final VoidCallback onAdd;
  // On-device paths of the picked files, for thumbnail previews.
  final List<String> paths;
  // Remove the file at this index (drops both preview + server key).
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

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
                        if (count > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.splashGreen
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
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
              const SizedBox(width: 8),
              busy
                  ? const SizedBox(
                      width: 28, height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : IconButton(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_circle, size: 32),
                      color: AppColors.splashGreen,
                      visualDensity: VisualDensity.compact,
                    ),
            ],
          ),
          if (paths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < paths.length; i++)
                  _PreviewTile(
                    path: paths[i],
                    onRemove: () => onRemove(i),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Preview tile ──────────────────────────────────────────────────────
// A small box per picked file: image thumbnail for photos, a file-type chip
// (extension label + icon) for PDFs / Office docs. A × badge removes it.
class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  static const double _size = 60;
  static const Set<String> _imageExts = {
    'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp',
  };

  String get _ext {
    final name = path.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : '';
  }

  bool get _isImage => _imageExts.contains(_ext);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBg = isDark ? const Color(0xFF14181A) : const Color(0xFFF1F2F4);
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    Widget body;
    if (_isImage) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(path),
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: _size,
            height: _size,
            color: chipBg,
            child: Icon(Icons.broken_image_outlined, size: 22, color: muted),
          ),
        ),
      );
    } else {
      body = Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 22, color: muted),
            const SizedBox(height: 4),
            Text(
              _ext.isEmpty
                  ? _IntakeStrings.file(Localizations.localeOf(context))
                  : _ext.toUpperCase(),
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

    return SizedBox(
      width: _size + 6,
      height: _size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 6, child: body),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Color(0xFFE5484D),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    required this.locale,
  });

  final TextEditingController floorCtrl;
  final TextEditingController totalFloorsCtrl;
  final ValueChanged<String> onFloorChanged;
  final ValueChanged<String> onTotalChanged;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _IntakeStrings.floorSectionTitle(locale),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _IntakeStrings.floorSectionSubtitle(locale),
          style: TextStyle(fontFamily: 'MTSCompact', fontSize: 12, color: muted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FloorField(
                label: _IntakeStrings.objectFloor(locale),
                controller: floorCtrl,
                onChanged: onFloorChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FloorField(
                label: _IntakeStrings.totalFloors(locale),
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


class _IntakeStrings {
  const _IntakeStrings._();

  static String title(Locale l) => switch (l.languageCode) {
        'ru' => 'Документы и фото',
        'en' => 'Documents and photos',
        _ => 'Hujjat va rasmlar',
      };

  static String subtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Необходимые данные для оценки',
        'en' => 'Information required for valuation',
        _ => 'Baholash uchun zarur maʼlumotlar',
      };

  static String photosTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Фото объекта',
        'en' => 'Property photos',
        _ => 'Obyekt rasmlari',
      };

  static String photosHint(Locale l) => switch (l.languageCode) {
        'ru' => 'Внутри и снаружи (1–15). Для оценки состояния.',
        'en' => 'Interior and exterior (1–15). For condition assessment.',
        _ => 'Ichki va tashqi (1-15). Holatni baholash uchun.',
      };

  static String kadastrTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Кадастровые документы',
        'en' => 'Cadastral documents',
        _ => 'Kadastr hujjatlari',
      };

  static String kadastrHint(Locale l) => switch (l.languageCode) {
        'ru' => 'Техпаспорт, план (1–20). Определяется площадь/год.',
        'en' => 'Tech passport, plan (1–20). Area/year are derived.',
        _ => 'Texpasport, plan (1-20). Maydon/yil aniqlanadi.',
      };

  static String passportTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Паспорт / ID (необязательно)',
        'en' => 'Passport / ID (optional)',
        _ => 'Pasport / ID (ixtiyoriy)',
      };

  static String passportHint(Locale l) => switch (l.languageCode) {
        'ru' => 'Данные владельца для отчёта.',
        'en' => "Owner's details for the report.",
        _ => 'Hisobot uchun egasining maʼlumoti.',
      };

  static String floorSectionTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Этаж',
        'en' => 'Floor',
        _ => 'Qavat',
      };

  static String floorSectionSubtitle(Locale l) => switch (l.languageCode) {
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

  static String roomsTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Комнаты (необязательно)',
        'en' => 'Rooms (optional)',
        _ => 'Xonalar (ixtiyoriy)',
      };

  static String roomsSubtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Выберите типы комнат, укажите количество',
        'en' => 'Select room types, enter the count',
        _ => 'Xona turlarini tanlang, sonini kiriting',
      };

  static String submitting(Locale l) => switch (l.languageCode) {
        'ru' => 'Отправка…',
        'en' => 'Submitting…',
        _ => 'Yuborilmoqda…',
      };

  static String calculate(Locale l) => switch (l.languageCode) {
        'ru' => 'Рассчитать',
        'en' => 'Calculate',
        _ => 'Hisoblash',
      };

  static String file(Locale l) => switch (l.languageCode) {
        'ru' => 'файл',
        'en' => 'file',
        _ => 'fayl',
      };

  static String maxPhotos(Locale l) => switch (l.languageCode) {
        'ru' => 'Не более 15 фото',
        'en' => 'Up to 15 photos',
        _ => "Koʻpi bilan 15 ta rasm",
      };

  static String maxFiles(Locale l, int n) => switch (l.languageCode) {
        'ru' => 'Не более $n файлов',
        'en' => 'Up to $n files',
        _ => "Koʻpi bilan $n ta fayl",
      };

  static String authRequired(Locale l) => switch (l.languageCode) {
        'ru' => 'Требуется авторизация',
        'en' => 'Authorization required',
        _ => 'Avtorizatsiya kerak',
      };

  static String uploadError(Locale l, String err) => switch (l.languageCode) {
        'ru' => 'Ошибка загрузки: $err',
        'en' => 'Upload error: $err',
        _ => 'Yuklashda xatolik: $err',
      };

  static String missingPhoto(Locale l) => switch (l.languageCode) {
        'ru' => 'фото',
        'en' => 'photo',
        _ => 'rasm',
      };

  static String missingKadastr(Locale l) => switch (l.languageCode) {
        'ru' => 'кадастровый документ',
        'en' => 'cadastral document',
        _ => 'kadastr hujjati',
      };

  static String missingRooms(Locale l) => switch (l.languageCode) {
        'ru' => 'комнаты',
        'en' => 'rooms',
        _ => 'xonalar',
      };

  static String missingFloor(Locale l) => switch (l.languageCode) {
        'ru' => 'этаж',
        'en' => 'floor',
        _ => 'qavat',
      };

  static String floorTooHigh(Locale l) => switch (l.languageCode) {
        'ru' => 'Этаж не может превышать общее число этажей в здании',
        'en' => 'The floor cannot exceed the total floors in the building',
        _ => "Qavat binodagi jami qavatlardan katta boʻlmasligi kerak",
      };

  static String missingRequired(Locale l, String fields) =>
      switch (l.languageCode) {
        'ru' => '$fields обязательны',
        'en' => '$fields are required',
        _ => '$fields majburiy',
      };
}
