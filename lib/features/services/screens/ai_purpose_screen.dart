/// AI Baholash wizard — purpose step (baholash maqsadi).
///
/// Required, single-select. Drives the backend's reconciliation weighting
/// (insurance→cost, sale→market, court→balanced …). After selecting,
/// continues to the intake step (photos / kadastr / passport / rooms).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../ai_draft_saver.dart';
import '../api_ai_valuation_job_service.dart';
import '../models/ai_baholash_bundle.dart';
import '../models/ai_wizard_steps.dart';
import '../widgets/choice_tile.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/wizard_nav_bar.dart';
import 'ai_intake_screen.dart';

class AiPurposeScreen extends StatefulWidget {
  const AiPurposeScreen({super.key, required this.bundle});

  final AiBaholashBundle bundle;

  @override
  State<AiPurposeScreen> createState() => _AiPurposeScreenState();
}

class _AiPurposeScreenState extends State<AiPurposeScreen> {
  late ValuationPurpose _purpose = widget.bundle.purpose;
  late final TextEditingController _basisCtrl =
      TextEditingController(text: widget.bundle.purposeBasis ?? '');
  late final TextEditingController _addresseeCtrl =
      TextEditingController(text: widget.bundle.addressee ?? '');

  final _api = AiValuationJobService();

  /// Purpose options from the backend (source of truth). `null` until loaded —
  /// the build falls back to the built-in [ValuationPurpose] list so the step
  /// renders instantly and still works offline.
  List<PurposeOption>? _options;

  /// "Baholash asosi" presets from the backend. `null` until loaded — until
  /// then (and offline) the basis falls back to a plain textarea.
  List<BasisOption>? _basisOptions;

  /// Selected basis option wire. `'other'` (or any non-preset) reveals the
  /// free-text textarea bound to [_basisCtrl].
  String? _basisValue;

  /// Last locale seen in build — used by dispose (Orqaga) to resolve the basis
  /// label without a BuildContext.
  Locale? _lastLocale;

  @override
  void initState() {
    super.initState();
    // A draft may carry free basis text — treat it as "other" until/unless it
    // matches a preset once the options load.
    if ((widget.bundle.purposeBasis ?? '').trim().isNotEmpty) {
      _basisValue = 'other';
    }
    _loadPurposes();
    _loadBasisOptions();
  }

  Future<void> _loadPurposes() async {
    try {
      final opts = await _api.fetchPurposeOptions();
      if (!mounted || opts.isEmpty) return;
      setState(() => _options = opts);
    } catch (_) {
      // Offline / server error → keep the built-in fallback list.
    }
  }

  Future<void> _loadBasisOptions() async {
    try {
      final opts = await _api.fetchBasisOptions();
      if (!mounted || opts.isEmpty) return;
      // If a draft prefilled free text that exactly matches a preset label,
      // snap the select to that preset instead of "other".
      final existing = (widget.bundle.purposeBasis ?? '').trim();
      String? matched;
      if (existing.isNotEmpty) {
        for (final o in opts) {
          if (o.isOther) continue;
          if (o.labelByLocale.values.any((v) => v.trim() == existing)) {
            matched = o.wire;
            break;
          }
        }
      }
      setState(() {
        _basisOptions = opts;
        if (matched != null) _basisValue = matched;
      });
    } catch (_) {
      // Offline / server error → keep the plain-textarea fallback.
    }
  }

  @override
  void dispose() {
    // Orqaga qaytishда ham fon rejimida saqlash.
    final l = _lastLocale;
    if (l != null) {
      _captureToBundle(l);
      saveAiDraftStepInBackground(widget.bundle, 'purpose');
    }
    _basisCtrl.dispose();
    _addresseeCtrl.dispose();
    super.dispose();
  }

  /// Resolve the basis text to store in `purpose_text`:
  /// - options not loaded (offline) → plain textarea text;
  /// - a preset selected → that preset's localized label;
  /// - "other" selected → the typed textarea text;
  /// - nothing selected → null.
  String? _resolveBasis(Locale l) {
    final opts = _basisOptions;
    final v = _basisValue;
    if (opts == null || v == null || v == 'other') {
      final t = _basisCtrl.text.trim();
      return t.isEmpty ? null : t;
    }
    for (final o in opts) {
      if (o.wire == v) return o.label(l.languageCode);
    }
    return null;
  }

  Future<void> _next() async {
    HapticFeedback.lightImpact();
    _captureToBundle(Localizations.localeOf(context));
    // Fon rejimida saqlash — sekin backend navigatsiyani muzlatmasin.
    saveAiDraftStepInBackground(widget.bundle, 'intake');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/intake'),
        builder: (_) => AiIntakeScreen(bundle: widget.bundle),
      ),
    );
  }

  /// Joriy maqsad/asos/kimga'ni bundle'ga yozadi (oldinga ham, Orqaga ham).
  void _captureToBundle(Locale l) {
    widget.bundle.purpose = _purpose;
    final addressee = _addresseeCtrl.text.trim();
    widget.bundle.purposeBasis = _resolveBasis(l);
    widget.bundle.addressee = addressee.isEmpty ? null : addressee;
  }

  Future<void> _pickBasis(Locale l) async {
    final opts = _basisOptions;
    if (opts == null) return;
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _BasisPickerSheet(options: opts, selected: _basisValue, locale: l),
    );
    if (picked != null && mounted) setState(() => _basisValue = picked);
  }

  String? _basisLabel(Locale l) {
    final opts = _basisOptions;
    final v = _basisValue;
    if (opts == null || v == null) return null;
    for (final o in opts) {
      if (o.wire == v) return o.label(l.languageCode);
    }
    return null;
  }

  /// The rows to render: backend options when loaded, otherwise the built-in
  /// enum so the step works before the fetch finishes (and offline).
  /// Credit-only purposes are no longer offered — drop any such option coming
  /// from the backend so only the approved purposes are shown.
  static bool _isCreditWire(String wire) {
    final w = wire.toLowerCase();
    return w.contains('credit') || w.contains('kredit') || w == 'loan';
  }

  List<({String wire, String label, String hint})> _purposeTiles(Locale l) {
    final opts = _options;
    if (opts != null) {
      // Backend is the single source of truth for wording/order — render its
      // labels directly (no local override), so options can change server-side
      // without an app release.
      final lang = l.languageCode;
      return [
        for (final o in opts)
          if (!_isCreditWire(o.wire))
            (wire: o.wire, label: o.label(lang), hint: ''),
      ];
    }
    // Offline / pre-fetch fallback: the built-in enum.
    return [
      for (final p in ValuationPurpose.values)
        (wire: p.wire, label: p.label(l), hint: ''),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    _lastLocale = l; // Orqaga ketishда (dispose) asos matnini hal qilish uchun.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

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
                    title: _PurposeStrings.title(l),
                    subtitle: _PurposeStrings.subtitle(l),
                    // Bu tugma butun oqimni yopadi — bitta qadam
                    // orqaga EMAS. Qadamma-qadam qaytish pastda.
                    onBack: () => confirmCloseAiWizard(context),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(
                    count: widget.bundle.aiStepCount,
                    activeIndex: widget.bundle.aiStepIndex(AiStep.purpose),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      for (final pt in _purposeTiles(l)) ...[
                        ChoiceTile(
                          label: pt.hint.isEmpty
                              ? pt.label
                              : '${pt.label}  ·  ${pt.hint}',
                          selected: _purpose.wire == pt.wire,
                          onTap: () => setState(
                            () => _purpose = ValuationPurpose.fromWire(pt.wire),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 8),
                      // Baholash asosi — backend preset'laridan select; "Boshqa"
                      // tanlansa erkin matn (textarea) ochiladi. Optionlar
                      // yuklanmaguncha / offline'da oddiy textarea ko'rsatiladi.
                      if (_basisOptions != null) ...[
                        _BasisSelectField(
                          label: _PurposeStrings.basisLabel(l),
                          valueText: _basisLabel(l),
                          placeholder: _PurposeStrings.basisSelectHint(l),
                          onTap: () => _pickBasis(l),
                        ),
                        if (_basisValue == 'other') ...[
                          const SizedBox(height: 12),
                          _LabeledField(
                            label: _PurposeStrings.basisOtherLabel(l),
                            hint: _PurposeStrings.basisHint(l),
                            controller: _basisCtrl,
                            minLines: 3,
                            maxLines: 5,
                          ),
                        ],
                      ] else
                        _LabeledField(
                          label: _PurposeStrings.basisLabel(l),
                          hint: _PurposeStrings.basisHint(l),
                          controller: _basisCtrl,
                          minLines: 3,
                          maxLines: 5,
                        ),
                      const SizedBox(height: 14),
                      // Кимга тақдим этилади — илова хатдаги адресат.
                      _LabeledField(
                        label: _PurposeStrings.addresseeLabel(l),
                        hint: _PurposeStrings.addresseeHint(l),
                        controller: _addresseeCtrl,
                        minLines: 1,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: WizardNavBar(
                    onBack: () => Navigator.of(context).maybePop(),
                    onContinue: _next,
                    continueLabel: _PurposeStrings.continueLabel(l),
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

class _PurposeStrings {
  const _PurposeStrings._();

  static String title(Locale l) => tr(l, 'services.ai.purpose.title');

  static String subtitle(Locale l) => tr(l, 'services.ai.purpose.subtitle');

  static String continueLabel(Locale l) => tr(l, 'services.ai.common.continue');

  static String basisLabel(Locale l) => tr(l, 'services.ai.purpose.basis_label');

  static String basisSelectHint(Locale l) =>
      tr(l, 'services.ai.purpose.basis_select_hint');

  static String basisOtherLabel(Locale l) =>
      tr(l, 'services.ai.purpose.basis_other_label');

  static String basisHint(Locale l) => tr(l, 'services.ai.purpose.basis_hint');

  static String addresseeLabel(Locale l) =>
      tr(l, 'services.ai.purpose.addressee_label');

  static String addresseeHint(Locale l) =>
      tr(l, 'services.ai.purpose.addressee_hint');
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.controller,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: muted,
            ),
          ),
        ),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          textInputAction:
              maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 14,
            height: 1.35,
            color: textColor,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 13,
              color: muted,
            ),
            filled: true,
            fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.splashGreen, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tappable "select" field — shows the picked label (or a placeholder) plus a
/// chevron; tapping opens [_BasisPickerSheet]. Mirrors [_LabeledField] styling.
class _BasisSelectField extends StatelessWidget {
  const _BasisSelectField({
    required this.label,
    required this.valueText,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final String? valueText;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    final hasValue = (valueText ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: muted,
            ),
          ),
        ),
        Material(
          color: fieldBg,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasValue ? valueText! : placeholder,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontSize: 14,
                        height: 1.3,
                        color: hasValue ? textColor : muted,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: muted, size: 22),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom-sheet list of basis options. Pops the picked option's wire value.
class _BasisPickerSheet extends StatelessWidget {
  const _BasisPickerSheet({
    required this.options,
    required this.selected,
    required this.locale,
  });

  final List<BasisOption> options;
  final String? selected;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF15191B) : Colors.white;
    final lang = locale.languageCode;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final o in options) ...[
                      ChoiceTile(
                        label: o.label(lang),
                        selected: selected == o.wire,
                        onTap: () => Navigator.of(context).pop(o.wire),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
