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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../api_ai_upload_service.dart';
import '../models/ai_baholash_bundle.dart';
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

  @override
  void dispose() {
    _uploads.dispose();
    super.dispose();
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
      _snack("Ko'pi bilan 15 ta rasm");
      return;
    }
    final List<XFile> picked = await _imagePicker.pickMultiImage(limit: remaining);
    if (picked.isEmpty) return;
    await _doUpload(
      category: UploadCategory.propertyPhoto,
      paths: picked.map((x) => x.path).toList(),
      target: widget.bundle.imageKeys,
      setBusy: (v) => setState(() => _photosBusy = v),
    );
  }

  // ── Kadastr docs (file_picker: images + pdf) ────────────────────────
  Future<void> _addKadastr() async {
    await _pickFilesUpload(
      category: UploadCategory.kadastr,
      target: widget.bundle.kadastrKeys,
      maxTotal: 20,
      setBusy: (v) => setState(() => _kadastrBusy = v),
    );
  }

  // ── Passport (file_picker, optional) ────────────────────────────────
  Future<void> _addPassport() async {
    await _pickFilesUpload(
      category: UploadCategory.passport,
      target: widget.bundle.passportKeys,
      maxTotal: 5,
      setBusy: (v) => setState(() => _passportBusy = v),
    );
  }

  Future<void> _pickFilesUpload({
    required UploadCategory category,
    required List<String> target,
    required int maxTotal,
    required void Function(bool) setBusy,
  }) async {
    final remaining = maxTotal - target.length;
    if (remaining <= 0) {
      _snack("Ko'pi bilan $maxTotal ta fayl");
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .take(remaining)
        .toList();
    await _doUpload(
      category: category, paths: paths, target: target, setBusy: setBusy);
  }

  Future<void> _doUpload({
    required UploadCategory category,
    required List<String> paths,
    required List<String> target,
    required void Function(bool) setBusy,
  }) async {
    if (paths.isEmpty) return;
    final token = await _token();
    if (token == null || token.isEmpty) {
      _snack('Avtorizatsiya kerak');
      return;
    }
    setBusy(true);
    try {
      final keys = await _uploads.upload(
        category: category, filePaths: paths, token: token);
      if (!mounted) return;
      setState(() => target.addAll(keys));
    } catch (e) {
      _snack('Yuklashda xatolik: $e');
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ServiceAppBar(
                    title: 'Hujjat va rasmlar',
                    subtitle: 'Aniqroq baho uchun (ixtiyoriy)',
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _UploadCard(
                        title: 'Obyekt rasmlari',
                        hint: 'Ichki va tashqi (1-15). Holatni baholash uchun.',
                        icon: Icons.photo_camera_outlined,
                        count: b.imageKeys.length,
                        busy: _photosBusy,
                        onAdd: _addPhotos,
                      ),
                      const SizedBox(height: 12),
                      _UploadCard(
                        title: 'Kadastr hujjatlari',
                        hint: 'Texpasport, plan (1-20). Maydon/yil aniqlanadi.',
                        icon: Icons.description_outlined,
                        count: b.kadastrKeys.length,
                        busy: _kadastrBusy,
                        onAdd: _addKadastr,
                      ),
                      const SizedBox(height: 12),
                      _UploadCard(
                        title: 'Pasport / ID (ixtiyoriy)',
                        hint: 'Hisobot uchun egasining ma\'lumoti.',
                        icon: Icons.badge_outlined,
                        count: b.passportKeys.length,
                        busy: _passportBusy,
                        onAdd: _addPassport,
                      ),
                      const SizedBox(height: 20),
                      _RoomsSelector(rooms: b.rooms),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _submitting ? 'Yuborilmoqda…' : 'Hisoblash',
                    enabled: !_submitting,
                    onTap: _calculate,
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
  });

  final String title;
  final String hint;
  final IconData icon;
  final int count;
  final bool busy;
  final VoidCallback onAdd;

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
      child: Row(
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
                          color: AppColors.splashGreen.withValues(alpha: 0.15),
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
    );
  }
}

// ── Rooms selector ────────────────────────────────────────────────────
// Chips shown inline under the title. Tap a chip to (de)select a room type;
// each selected type gets its own row below with a typeable count + stepper.
class _RoomsSelector extends StatefulWidget {
  const _RoomsSelector({required this.rooms});

  /// The bundle's room list — mutated in place as the user selects/edits.
  final List<AiRoom> rooms;

  @override
  State<_RoomsSelector> createState() => _RoomsSelectorState();
}

class _RoomsSelectorState extends State<_RoomsSelector> {
  // Standard room kinds shown as toggle chips (everything except `other`).
  static final List<RoomKind> _standardKinds =
      RoomKind.values.where((k) => k != RoomKind.other).toList();

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
  }

  void _remove(AiRoom room) {
    setState(() {
      widget.rooms.remove(room);
      _counts.remove(room)?.dispose();
    });
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    final selectedKinds = widget.rooms.map((r) => r.kind).toSet();
    final hasCustom = widget.rooms.any((r) => r.kind == RoomKind.other);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Xonalar (ixtiyoriy)',
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Xona turlarini tanlang, sonini kiriting',
          style: TextStyle(fontFamily: 'MTSCompact', fontSize: 12, color: muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in _standardKinds)
              _RoomChip(
                label: k.labelUz,
                selected: selectedKinds.contains(k),
                onTap: () => _toggleStandard(k),
              ),
            // "Boshqa" opens a custom-name input instead of adding a fixed row.
            _RoomChip(
              label: RoomKind.other.labelUz,
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
                      : 'Boshqa')
                  : room.kind.labelUz,
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
              decoration: const InputDecoration(
                hintText: 'Xona nomi (masalan: Ish xonasi)',
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
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
