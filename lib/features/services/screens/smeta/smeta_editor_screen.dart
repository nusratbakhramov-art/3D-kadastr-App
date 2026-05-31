/// Professional smeta editor — header + sections + line items, then
/// "Calculate" → submits to `/abc4/jobs` and opens the result screen.
///
/// State lives in a `SmetaDraft` (ChangeNotifier). The editor is loose by
/// design: user adds sections, picks lines from the СНиР catalog, enters
/// quantities. No client-side pricing — ABC does the math.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/smeta_api_service.dart';
import '../../models/smeta_draft.dart';
import '../../widgets/service_app_bar.dart';
import 'code_search_sheet.dart';
import 'smeta_result_screen.dart';

class SmetaEditorScreen extends StatefulWidget {
  const SmetaEditorScreen({super.key, this.service});

  final SmetaApiService? service;

  @override
  State<SmetaEditorScreen> createState() => _SmetaEditorScreenState();
}

class _SmetaEditorScreenState extends State<SmetaEditorScreen> {
  late final SmetaApiService _service = widget.service ?? SmetaApiService();
  final SmetaDraft _draft = SmetaDraft();
  final TextEditingController _objectName = TextEditingController();
  final TextEditingController _estimateName = TextEditingController();
  final TextEditingController _district = TextEditingController(text: '1');

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _draft.removeListener(_onDraftChanged);
    _draft.dispose();
    _objectName.dispose();
    _estimateName.dispose();
    _district.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  bool get _ready => _draft.itemCount > 0 && !_submitting;

  Future<void> _addSection() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yangi bo\'lim'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Bo'lim nomi",
            hintText: 'Masalan: Yer ishlari',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text("Qo'shish"),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.trim().isEmpty) return;
    _draft.addSection(SmetaSection(
      code: '${_draft.sections.length + 1}',
      name: name.trim(),
    ));
  }

  Future<void> _addItem(int sectionIndex) async {
    final item = await showCodeSearchSheet(context, service: _service);
    if (item == null) return;
    _draft.addItem(sectionIndex, item);
  }

  Future<void> _calculate() async {
    if (!_ready) return;
    HapticFeedback.lightImpact();

    // sync header text fields → draft
    _draft.texts.objectName = _objectName.text.trim();
    _draft.texts.estimateName = _estimateName.text.trim();
    _draft.header.district = _district.text.trim().isEmpty
        ? '1'
        : _district.text.trim();

    setState(() => _submitting = true);
    try {
      final snap = await _service.enqueue(_draft);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SmetaResultScreen(jobId: snap.id, service: _service),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xatolik: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: 'Smeta tuzish',
                        subtitle: 'ABC-UZ asosida professional smeta',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          const _Label('Obyekt nomi'),
                          _Field(
                            controller: _objectName,
                            hint: 'Masalan: Yakka tartibdagi turar-joy',
                          ),
                          const SizedBox(height: 12),
                          const _Label('Smeta nomi'),
                          _Field(
                            controller: _estimateName,
                            hint: 'Masalan: Yer va beton ishlari',
                          ),
                          const SizedBox(height: 12),
                          const _Label('Rayon kodi'),
                          _Field(
                            controller: _district,
                            hint: '1',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Expanded(
                                child: _Label("Bo'limlar va pozitsiyalar"),
                              ),
                              TextButton.icon(
                                onPressed: _addSection,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text("Bo'lim"),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_draft.sections.isEmpty)
                            const _EmptySections()
                          else
                            for (var i = 0; i < _draft.sections.length; i++)
                              _SectionCard(
                                section: _draft.sections[i],
                                onAddItem: () => _addItem(i),
                                onRemoveSection: () => _draft.removeSection(i),
                                onRemoveItem: (j) => _draft.removeItem(i, j),
                              ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: _submitting
                            ? 'Yuborilmoqda...'
                            : 'Hisoblash (${_draft.itemCount} pozitsiya)',
                        enabled: _ready,
                        onTap: _calculate,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white70 : const Color(0xFF6C7278);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: color,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.onAddItem,
    required this.onRemoveSection,
    required this.onRemoveItem,
  });

  final SmetaSection section;
  final VoidCallback onAddItem;
  final VoidCallback onRemoveSection;
  final void Function(int) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final mutedColor =
        isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${section.code}. ${section.name}',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onRemoveSection,
                tooltip: "Bo'limni o'chirish",
                color: mutedColor,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (section.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Pozitsiya yo\'q',
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontSize: 12,
                  color: mutedColor,
                ),
              ),
            )
          else
            for (var j = 0; j < section.items.length; j++)
              _ItemRow(
                item: section.items[j],
                onRemove: () => onRemoveItem(j),
                muted: mutedColor,
                text: textColor,
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddItem,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Pozitsiya'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onRemove,
    required this.muted,
    required this.text,
  });

  final SmetaItem item;
  final VoidCallback onRemove;
  final Color muted;
  final Color text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.code,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.splashGreen,
                  ),
                ),
                Text(
                  item.name,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontSize: 12,
                    height: 1.3,
                    color: text,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(item.quantity)} ${item.unit}',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontSize: 11,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            color: muted,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}

class _EmptySections extends StatelessWidget {
  const _EmptySections();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.add_chart, size: 28, color: muted),
          const SizedBox(height: 8),
          Text(
            "Boshlash uchun \"Bo'lim\" tugmasini bosing",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 13,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}
