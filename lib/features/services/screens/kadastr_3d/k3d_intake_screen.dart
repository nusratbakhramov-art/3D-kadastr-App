/// Step 4 of 3D Kadastr — intake (hujjat va rasmlar).
///
/// Mirrors the AI Baholash intake (`ai_intake_screen.dart`) **without** the
/// owner passport/ID section. Three sections on one scrollable screen:
///   • Property photos (inside/outside, 1-15)
///   • Kadastr documents (1-20)
///   • Floor + rooms breakdown
///
/// Files are uploaded to `/3d-kadastr-jobs/upload` the moment they're picked;
/// the returned keys are stored on the bundle. "Davom etish" proceeds to the
/// LiDAR scan step.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../../settings/settings_state.dart';
import '../../api_ai_upload_service.dart';
import '../../models/ai_baholash_bundle.dart' show AiRoom, RoomKind;
import '../../models/kadastr_3d_bundle.dart';
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

  bool _photosBusy = false;
  bool _kadastrBusy = false;

  // On-device paths, index-aligned with the bundle's key lists (for previews).
  final List<String> _photoPaths = [];
  final List<String> _kadastrPaths = [];

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

  // Photos, kadastr docs, rooms, and both floor numbers are mandatory.
  // Backend caps total_floors at 200 — validate client-side for a friendly
  // hint instead of a raw 422.
  static const int _maxFloors = 200;

  bool get _ready =>
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
    final missing = <String>[];
    if (widget.bundle.imageKeys.isEmpty) missing.add(_Strings.missingPhoto(l));
    if (widget.bundle.kadastrKeys.isEmpty) {
      missing.add(_Strings.missingKadastr(l));
    }
    if (widget.bundle.rooms.isEmpty) missing.add(_Strings.missingRooms(l));
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addPhotos() async {
    final remaining = 15 - widget.bundle.imageKeys.length;
    if (remaining <= 0) {
      _snack(_Strings.maxPhotos(localeNotifier.value, 15));
      return;
    }
    final List<XFile> picked =
        await _imagePicker.pickMultiImage(limit: remaining);
    if (picked.isEmpty) return;
    await _doUpload(
      category: UploadCategory.propertyPhoto,
      paths: picked.map((x) => x.path).toList(),
      target: widget.bundle.imageKeys,
      targetPaths: _photoPaths,
      setBusy: (v) => setState(() => _photosBusy = v),
    );
  }

  Future<void> _addKadastr() async {
    await _pickFilesUpload(
      category: UploadCategory.kadastr,
      target: widget.bundle.kadastrKeys,
      targetPaths: _kadastrPaths,
      maxTotal: 20,
      setBusy: (v) => setState(() => _kadastrBusy = v),
    );
  }

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
      _snack(_Strings.maxFiles(localeNotifier.value, maxTotal));
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
      _snack(_Strings.authRequired(localeNotifier.value));
      return;
    }
    setBusy(true);
    try {
      final keys = await _uploads.upload(
        category: category,
        filePaths: paths,
        token: token,
        endpoint: _kUploadEndpoint,
      );
      if (!mounted) return;
      setState(() {
        target.addAll(keys);
        targetPaths.addAll(paths.take(keys.length));
      });
    } catch (e) {
      _snack(_Strings.uploadError(localeNotifier.value, '$e'));
    } finally {
      if (mounted) setBusy(false);
    }
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
                    title: _Strings.appBarTitle(l),
                    subtitle: _Strings.appBarSubtitle(l),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(count: 6, activeIndex: 4),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      _UploadCard(
                        title: _Strings.objectPhotos(l),
                        hint: _Strings.objectPhotosHint(l),
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
                        title: _Strings.kadastrDocs(l),
                        hint: _Strings.kadastrDocsHint(l),
                        icon: Icons.description_outlined,
                        count: b.kadastrKeys.length,
                        busy: _kadastrBusy,
                        onAdd: _addKadastr,
                        paths: _kadastrPaths,
                        onRemove: (i) =>
                            _removeAt(b.kadastrKeys, _kadastrPaths, i),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_missingHint != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 15, color: Color(0xFFE5A23D)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _missingHint!,
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
                        label: _Strings.ctaContinue(l),
                        enabled: _ready,
                        onTap: _continue,
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
  final List<String> paths;
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
    final l = Localizations.localeOf(context);
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
              _ext.isEmpty ? _Strings.file(l) : _ext.toUpperCase(),
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
          style: TextStyle(fontFamily: 'MTSCompact', fontSize: 12, color: muted),
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
          _Strings.rooms(l),
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

class _Strings {
  const _Strings._();

  static String appBarTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Документы и фото',
        'en' => 'Documents and photos',
        _ => 'Hujjat va rasmlar',
      };

  static String appBarSubtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Необходимые данные для 3D модели',
        'en' => 'Data required for the 3D model',
        _ => '3D model uchun zarur ma\'lumotlar',
      };

  static String ctaContinue(Locale l) => switch (l.languageCode) {
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

  static String rooms(Locale l) => switch (l.languageCode) {
        'ru' => 'Комнаты',
        'en' => 'Rooms',
        _ => 'Xonalar',
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

  static String uploadError(Locale l, String e) => switch (l.languageCode) {
        'ru' => 'Ошибка загрузки: $e',
        'en' => 'Upload error: $e',
        _ => 'Yuklashda xatolik: $e',
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
