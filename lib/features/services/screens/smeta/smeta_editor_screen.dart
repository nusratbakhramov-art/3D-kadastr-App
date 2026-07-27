/// Professional smeta editor — header + sections + line items, then
/// "Calculate" → submits to `/abc4/jobs` and opens the result screen.
///
/// State lives in a `SmetaDraft` (ChangeNotifier). The editor is loose by
/// design: user adds sections, picks lines from the СНиР catalog, enters
/// quantities. No client-side pricing — ABC does the math.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n.dart';
import '../../../../core/i18n/app_translations.dart';
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
    final locale = Localizations.localeOf(context);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(locale, 'services.smeta.new_section')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr(locale, 'services.smeta.section_name'),
            hintText: tr(locale, 'services.smeta.section_name_hint'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L.cancel(locale)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(L.add(locale)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.trim().isEmpty) return;
    _draft.addSection(
      SmetaSection(code: '${_draft.sections.length + 1}', name: name.trim()),
    );
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
        SnackBar(
          content: Text(
            '${tr(Localizations.localeOf(context), 'services.smeta.error')}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
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
                        title: tr(locale, 'services.smeta.editor_title'),
                        subtitle: tr(locale, 'services.smeta.editor_subtitle'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          _Label(tr(locale, 'services.smeta.object_name')),
                          _Field(
                            controller: _objectName,
                            hint: tr(locale, 'services.smeta.object_name_hint'),
                          ),
                          const SizedBox(height: 12),
                          _Label(tr(locale, 'services.smeta.estimate_name')),
                          _Field(
                            controller: _estimateName,
                            hint: tr(locale, 'services.smeta.estimate_name_hint'),
                          ),
                          const SizedBox(height: 12),
                          _Label(tr(locale, 'services.smeta.district_code')),
                          _Field(
                            controller: _district,
                            hint: '1',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _Label(
                                  tr(locale, 'services.smeta.sections_and_items'),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _addSection,
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(tr(locale, 'services.smeta.section')),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_draft.sections.isEmpty)
                            _EmptySections(locale: locale)
                          else
                            for (var i = 0; i < _draft.sections.length; i++)
                              _SectionCard(
                                section: _draft.sections[i],
                                locale: locale,
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
                            ? tr(locale, 'services.smeta.submitting')
                            : '${tr(locale, 'services.smeta.calculate_prefix')} (${_draft.itemCount} ${tr(locale, 'services.smeta.items_unit')})',
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.locale,
    required this.onAddItem,
    required this.onRemoveSection,
    required this.onRemoveItem,
  });

  final SmetaSection section;
  final Locale locale;
  final VoidCallback onAddItem;
  final VoidCallback onRemoveSection;
  final void Function(int) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final mutedColor = isDark
        ? const Color(0xFF9BA1A6)
        : const Color(0xFF6C7278);

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
                tooltip: tr(locale, 'services.smeta.delete_section'),
                color: mutedColor,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (section.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                tr(locale, 'services.smeta.no_items'),
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
              label: Text(tr(locale, 'services.smeta.item')),
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
  const _EmptySections({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
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
            tr(locale, 'services.smeta.tap_section_to_start'),
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
