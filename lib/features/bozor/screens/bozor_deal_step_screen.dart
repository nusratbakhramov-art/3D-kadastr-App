/// "Bozor AI" sehrgarining 4/8-qadami — `Сделка`.
///
/// FAQAT SOTUV oqimida chiziladi ([wizardStepsFor]): ijara dizaynida bunday
/// qadam yo'q va backend ham ijara e'lonida bu bo'limni 400 bilan rad etadi
/// (`ListingCreateRequest.check_deal()`).
///
/// To'rtta select, hammasi backend ro'yxatlaridan (`/listings/options`).
/// Qiymat sifatida KOD saqlanadi (`free_sale`, `under_3`, `6_plus`), ekranda
/// esa shu tildagi yorliq ko'rinadi — til almashganda tanlov o'zgarmasin.
///
/// «Прописано» faqat kvartira turlarida ([PropertyTypeX.asksRegisteredCount]):
/// dizaynda Дом va Гараж freymlarida bu qator umuman yo'q.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../../services/widgets/wizard_nav_bar.dart';
import '../bozor_routes.dart';
import '../data/bozor_api.dart';
import '../data/bozor_draft_store.dart';
import '../data/param_options.dart';
import '../models/bozor_draft.dart';
import '../widgets/option_picker_sheet.dart';
import '../widgets/select_field.dart';
import 'bozor_price_step_screen.dart';

class BozorDealStepScreen extends StatefulWidget {
  const BozorDealStepScreen({
    super.key,
    required this.draft,
    this.optionsRepository,
  });

  final BozorDraft draft;

  /// Faqat testlar uchun — tarmoqqa chiqmasdan ro'yxat berish.
  final ParamOptionsRepository? optionsRepository;

  @override
  State<BozorDealStepScreen> createState() => _BozorDealStepScreenState();
}

class _BozorDealStepScreenState extends State<BozorDealStepScreen> {
  ParamOptionsRepository? _options;

  /// Ro'yxat kaliti → variantlar. Chizishdan oldin to'ldiriladi.
  final Map<String, List<ListingOption>> _lists = {};
  bool _loading = true;

  TransactionDraft get _t => widget.draft.transaction;

  /// Shu ekranda chiziladigan qatorlar — «Прописано» turga bog'liq.
  List<_DealRow> get _rows => [
    const _DealRow(
      optionsKey: 'sale_type',
      labelKey: 'bozor.transaction.sale_type',
    ),
    const _DealRow(
      optionsKey: 'ownership_years',
      labelKey: 'bozor.transaction.ownership_years',
    ),
    const _DealRow(
      optionsKey: 'owners_count',
      labelKey: 'bozor.transaction.owners_count',
      required: true,
    ),
    if (widget.draft.type?.asksRegisteredCount ?? false)
      const _DealRow(
        optionsKey: 'registered_count',
        labelKey: 'bozor.transaction.registered_count',
      ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_options != null) return;
    _options =
        widget.optionsRepository ??
        ApiParamOptions(locale: Localizations.localeOf(context).languageCode);
    _load();
  }

  /// Ro'yxatlarni oldindan yuklaydi — pickerda kutish bo'lmasin.
  ///
  /// Xato JIM yutiladi va qatorlar bo'sh ro'yxat bilan qoladi: pickerni
  /// ochib bo'lmaydi, lekin ekranning o'zi ochiladi va foydalanuvchi orqaga
  /// qaytib qoralamasini yo'qotmaydi.
  Future<void> _load() async {
    for (final row in _rows) {
      try {
        _lists[row.optionsKey] = await _options!.options(row.optionsKey);
      } catch (_) {
        _lists[row.optionsKey] = const [];
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  String? _valueOf(_DealRow row) => switch (row.optionsKey) {
    'sale_type' => _t.saleType,
    'ownership_years' => _t.ownershipYears,
    'owners_count' => _t.ownersCount,
    'registered_count' => _t.registeredCount,
    _ => null,
  };

  void _setValue(_DealRow row, String? code) {
    switch (row.optionsKey) {
      case 'sale_type':
        _t.saleType = code;
      case 'ownership_years':
        _t.ownershipYears = code;
      case 'owners_count':
        _t.ownersCount = code;
      case 'registered_count':
        _t.registeredCount = code;
    }
  }

  /// Saqlangan KODga mos yorliq. Ro'yxat kelmagan yoki kod eskirgan bo'lsa
  /// kodning o'zi ko'rsatiladi — bo'sh qator qolgandan yaxshi.
  String? _labelOf(_DealRow row) {
    final code = _valueOf(row);
    if (code == null) return null;
    final opts = _lists[row.optionsKey] ?? const [];
    return opts.where((o) => o.code == code).firstOrNull?.label ?? code;
  }

  Future<void> _pick(_DealRow row, String label) async {
    final opts = _lists[row.optionsKey] ?? const [];
    if (opts.isEmpty) return;
    final current = _valueOf(row);
    final picked = await showOptionPickerSheet<ListingOption>(
      context,
      title: label,
      options: opts,
      labelOf: (o) => o.label,
      selected: opts.where((o) => o.code == current).firstOrNull,
    );
    if (picked == null || !mounted) return;
    setState(() => _setValue(row, picked.code));
  }

  /// Dizaynda 4/8 dagi YAGONA majburiy maydon — «Собственники».
  bool get _isComplete => (_t.ownersCount ?? '').isNotEmpty;

  Future<void> _openPrice() async {
    // Qoralamani fonda saqlaymiz: foydalanuvchi shu qadamda chiqib ketsa
    // "Mening e'lonlarim" dan aynan shu joydan davom etadi.
    // `await` QILINMAYDI — tarmoq navigatsiyani muzlatmasin.
    saveBozorDraftInBackground(widget.draft, WizardStep.price);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('price'),
        builder: (_) => BozorPriceStepScreen(draft: widget.draft),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final draft = widget.draft;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxContent = c.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: tr(l, 'bozor.transaction.title'),
                        subtitle:
                            '${draft.stepNumber(WizardStep.deal)}'
                            '/${draft.stepCount}',
                        onBack: () => closeBozorWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: draft.stepCount,
                        activeIndex: draft.stepIndex(WizardStep.deal),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          for (final row in _rows) ...[
                            SelectField(
                              label: tr(l, row.labelKey),
                              value: _labelOf(row),
                              placeholder: _loading
                                  ? tr(l, 'bozor.common.loading')
                                  : tr(l, 'bozor.common.choose'),
                              enabled: !_loading,
                              required: row.required,
                              onTap: () => _pick(row, tr(l, row.labelKey)),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: WizardNavBar(
                        onBack: () => Navigator.of(context).maybePop(),
                        continueLabel: tr(l, 'bozor.common.next'),
                        continueEnabled: _isComplete,
                        onContinue: _openPrice,
                        onBlockedTap: () => AppToast.error(
                          context,
                          '${tr(l, 'bozor.common.fill_required')}: '
                          '${tr(l, 'bozor.transaction.owners_count')}',
                        ),
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

/// Ekrandagi bitta qator. Maydonlar to'rttagina, shuning uchun
/// `param_schema.dart` kabi to'liq jadval ortiqcha — lekin qator ta'rifi
/// baribir MA'LUMOT bo'lib tursin, aks holda to'rtta select qo'lda
/// takrorlanardi.
class _DealRow {
  const _DealRow({
    required this.optionsKey,
    required this.labelKey,
    this.required = false,
  });

  /// `/listings/options` dagi ro'yxat kaliti — backend bilan AYNAN bir xil.
  final String optionsKey;
  final String labelKey;
  final bool required;
}
