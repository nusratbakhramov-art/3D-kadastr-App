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

  // ── Rooms (optional, inline) ────────────────────────────────────────
  Future<void> _addRoom() async {
    final room = await showModalBottomSheet<AiRoom>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RoomSheet(),
    );
    if (room == null) return;
    setState(() => widget.bundle.rooms.add(room));
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
                      _RoomsSection(
                        rooms: b.rooms,
                        onAdd: _addRoom,
                        onRemove: (i) => setState(() => b.rooms.removeAt(i)),
                      ),
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

// ── Rooms section ─────────────────────────────────────────────────────
class _RoomsSection extends StatelessWidget {
  const _RoomsSection({
    required this.rooms,
    required this.onAdd,
    required this.onRemove,
  });

  final List<AiRoom> rooms;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Xonalar (ixtiyoriy)',
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: muted,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Xona'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (rooms.isEmpty)
          Text(
            'Xona qo\'shilmagan',
            style: TextStyle(
              fontFamily: 'MTSCompact', fontSize: 12, color: muted),
          )
        else
          for (var i = 0; i < rooms.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${rooms[i].count > 1 ? '${rooms[i].count} ' : ''}'
                      '${(rooms[i].name?.trim().isNotEmpty ?? false) ? rooms[i].name!.trim() : rooms[i].kind.labelUz}'
                      '${rooms[i].area != null ? ' · ${rooms[i].area!.toStringAsFixed(rooms[i].area! % 1 == 0 ? 0 : 1)} m²' : ''}',
                      style: TextStyle(
                        fontFamily: 'MTSCompact', fontSize: 14, color: textColor),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onRemove(i),
                    color: muted,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

// ── Add-room bottom sheet ─────────────────────────────────────────────
class _RoomSheet extends StatefulWidget {
  const _RoomSheet();

  @override
  State<_RoomSheet> createState() => _RoomSheetState();
}

class _RoomSheetState extends State<_RoomSheet> {
  RoomKind _kind = RoomKind.bedroom;
  int _count = 1;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _area = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  void _save() {
    final area = double.tryParse(_area.text.replaceAll(',', '.'));
    Navigator.of(context).pop(AiRoom(
      kind: _kind,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      count: _count,
      area: (area != null && area > 0) ? area : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF15191B) : Colors.white;
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Xona qo\'shish',
                style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in RoomKind.values)
                  ChoiceChip(
                    label: Text(k.labelUz),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nom (ixtiyoriy)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _area,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Maydon m² (ixtiyoriy)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _CountStepper(
                  value: _count,
                  onChanged: (v) => setState(() => _count = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Qo\'shish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountStepper extends StatelessWidget {
  const _CountStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Text('$value',
            style: const TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < 20 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
