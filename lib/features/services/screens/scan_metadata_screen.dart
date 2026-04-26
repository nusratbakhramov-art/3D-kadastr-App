import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/scan_draft.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';

const _viloyatlar = <String>[
  'Toshkent shahri',
  'Toshkent viloyati',
  'Andijon',
  'Buxoro',
  'Farg\'ona',
  'Jizzax',
  'Namangan',
  'Navoiy',
  'Qashqadaryo',
  'Qoraqalpog\'iston',
  'Samarqand',
  'Sirdaryo',
  'Surxondaryo',
  'Xorazm',
];

const _tumanlarByViloyat = <String, List<String>>{
  'Toshkent shahri': [
    'Bektemir',
    'Chilonzor',
    'Mirobod',
    'Mirzo Ulug\'bek',
    'Olmazor',
    'Sirg\'ali',
    'Shayxontohur',
    'Uchtepa',
    'Yakkasaroy',
    'Yashnobod',
    'Yunusobod',
  ],
  'Toshkent viloyati': [
    'Bekobod',
    'Bo\'ka',
    'Chinoz',
    'Ohangaron',
    'Olmaliq',
    'Parkent',
    'Piskent',
    'Quyichirchiq',
    'O\'rtachirchiq',
    'Yangiyo\'l',
    'Zangiota',
  ],
};

class ScanMetadataScreen extends StatefulWidget {
  const ScanMetadataScreen({super.key, required this.draft});

  final ScanDraft draft;

  @override
  State<ScanMetadataScreen> createState() => _ScanMetadataScreenState();
}

class _ScanMetadataScreenState extends State<ScanMetadataScreen> {
  String? _viloyat;
  String? _tuman;

  @override
  void initState() {
    super.initState();
    _viloyat = widget.draft.viloyat;
    _tuman = widget.draft.tuman;
  }

  bool get _ready => _viloyat != null && _tuman != null;

  Future<void> _pickViloyat() async {
    final v = await _showPicker(
      title: 'Viloyatni tanlang',
      options: _viloyatlar,
      current: _viloyat,
    );
    if (v == null || !mounted) return;
    setState(() {
      _viloyat = v;
      // Reset tuman if no longer valid for the new viloyat.
      if (_tuman != null &&
          !(_tumanlarByViloyat[v] ?? const []).contains(_tuman)) {
        _tuman = null;
      }
    });
  }

  Future<void> _pickTuman() async {
    if (_viloyat == null) return;
    final options = _tumanlarByViloyat[_viloyat!] ?? const <String>[];
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Tumanlar ro\'yxati tez orada'),
        ),
      );
      return;
    }
    final t = await _showPicker(
      title: 'Tumanni tanlang',
      options: options,
      current: _tuman,
    );
    if (t == null || !mounted) return;
    setState(() => _tuman = t);
  }

  Future<String?> _showPicker({
    required String title,
    required List<String> options,
    required String? current,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : AppColors.textBlack;
        final divider = isDark
            ? const Color(0xFF2C3133)
            : const Color(0xFFEEF0F2);
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: options.length,
                    separatorBuilder: (_, _) =>
                        Container(height: 1, color: divider),
                    itemBuilder: (_, i) {
                      final value = options[i];
                      final selected = value == current;
                      return InkWell(
                        onTap: () => Navigator.of(sheetContext).pop(value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  value,
                                  style: TextStyle(
                                    fontFamily: 'MTSText',
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    fontSize: 15,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.splashGreen,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submit() {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Skan yuborildi. To\'lov tez orada'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContent = constraints.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: const ServiceAppBar(
                        title: '3D kadastr',
                        subtitle: 'Ma\'lumotlarni tasdiqlang',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 4, activeIndex: 3),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          _SectionLabel('Hudud', color: labelColor),
                          const SizedBox(height: 10),
                          _PickerField(
                            placeholder: 'Viloyatni tanlang',
                            value: _viloyat,
                            onTap: _pickViloyat,
                          ),
                          const SizedBox(height: 10),
                          _PickerField(
                            placeholder: 'Tumanni tanlang',
                            value: _tuman,
                            onTap: _viloyat == null ? null : _pickTuman,
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel('Xulosa', color: labelColor),
                          const SizedBox(height: 10),
                          _SummaryCard(draft: widget.draft),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: 'To\'lov qilish va yuklab olish',
                        enabled: _ready,
                        onTap: _submit,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: 'MTSCompact',
      fontWeight: FontWeight.w700,
      fontSize: 16,
      height: 1.25,
      color: color,
    ),
  );
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.placeholder,
    required this.value,
    required this.onTap,
  });

  final String placeholder;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);
    final disabled = onTap == null;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value ?? placeholder,
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontWeight: value == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                    fontSize: 15,
                    color: value == null
                        ? hintColor
                        : (disabled
                              ? textColor.withValues(alpha: 0.5)
                              : textColor),
                  ),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 22,
                color: disabled
                    ? hintColor
                    : (isDark ? Colors.white70 : const Color(0xFF8A9097)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.draft});

  final ScanDraft draft;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    final rows = <(String, String)>[
      ('Kadastr raqami', draft.cadastreNumber),
      ('Obyekt turi', draft.objectType?.label ?? '—'),
      ('Skan', draft.scanCompleted ? 'Tayyor' : 'Kutilmoqda'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rows[i].$1,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 13,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    rows[i].$2,
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.25,
                      color: valueColor,
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1) Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}
