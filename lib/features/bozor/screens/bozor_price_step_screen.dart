/// "Bozor AI" sehrgarining narx qadami — `Цена`.
///
/// Qadam RAQAMI turga bog'liq: "Boshqa noturar joy" da parametrlar qadami
/// yo'q, shuning uchun narx uchinchi bo'ladi (`3/6`), qolganlarida to'rtinchi
/// (`4/7`). Raqam qo'lda yozilmaydi — [BozorDraft.stepNumber] beradi.
///
/// Sutkalik narx qatori faqat kvartira va uyda ko'rinadi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../../services/widgets/wizard_field.dart';
import '../../services/widgets/wizard_nav_bar.dart';
import '../bozor_routes.dart';
import '../data/bozor_draft_store.dart';
import '../models/bozor_draft.dart';
import '../widgets/option_picker_sheet.dart';
import '../widgets/price_field.dart';
import 'bozor_description_step_screen.dart';

/// Birlik tokenlari.
///
/// Dizaynda ro'yxat ochiq holda chizilmagan; valyutani almashtirish mumkin
/// deb qabul qildik, davr esa qatorga biriktirilgan.
///
/// ⚠️ SOTUVDA DAVR YO'Q. Ijara narxi oylik (`UZS/oy`), sotuv narxi esa bir
/// martalik summa (`UZS`) — dizaynda hech bir sotuv freymida «/мес» yo'q.
/// Sotuvga davrli token yuborilsa e'lon lentada «450 000 000 soʻm/oy» bo'lib
/// chiqardi.
const List<String> _monthlyUnits = ['UZS/oy', 'USD/oy'];
const List<String> _saleUnits = ['UZS', 'USD'];
const List<String> _dailyUnits = ['UZS', 'USD'];

class BozorPriceStepScreen extends StatefulWidget {
  const BozorPriceStepScreen({super.key, required this.draft});

  final BozorDraft draft;

  @override
  State<BozorPriceStepScreen> createState() => _BozorPriceStepScreenState();
}

class _BozorPriceStepScreenState extends State<BozorPriceStepScreen> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.draft.price.amount);
  late final TextEditingController _daily =
      TextEditingController(text: widget.draft.price.dailyAmount);

  PriceDraft get _p => widget.draft.price;

  /// Sutkalik narx faqat turar joyda VA faqat ijarada — dizaynda uchastka,
  /// tijorat, garaj va boshqa noturar joyda bu qator umuman yo'q (kartaning
  /// balandligi ham 283 emas, 197), sotuv freymlarida esa hech qayerda yo'q.
  bool get _hasDailyPrice =>
      widget.draft.deal != DealType.sale &&
      (widget.draft.type == PropertyType.apartment ||
          widget.draft.type == PropertyType.newBuildingApartment ||
          widget.draft.type == PropertyType.house);

  bool get _isSale => widget.draft.deal == DealType.sale;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmount);
    _daily.addListener(_onDaily);
  }

  @override
  void dispose() {
    _amount.removeListener(_onAmount);
    _daily.removeListener(_onDaily);
    _amount.dispose();
    _daily.dispose();
    super.dispose();
  }

  void _onAmount() => setState(() => _p.amount = _amount.text.trim());
  void _onDaily() => setState(() => _p.dailyAmount = _daily.text.trim());

  Future<void> _pickUnit({required bool daily}) async {
    final l = Localizations.localeOf(context);
    final picked = await showOptionPickerSheet<String>(
      context,
      title: tr(l, 'bozor.price.unit_title'),
      options: daily
          ? _dailyUnits
          : (_isSale ? _saleUnits : _monthlyUnits),
      labelOf: (o) => o,
      selected: daily ? _p.dailyUnit : _p.unit,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (daily) {
        _p.dailyUnit = picked;
      } else {
        _p.unit = picked;
      }
    });
  }

  Future<void> _openDescription() async {
    // Qoralamani fonda saqlaymiz: foydalanuvchi shu qadamda chiqib
    // ketsa "Mening e'lonlarim" dan aynan shu joydan davom etadi.
    // `await` QILINMAYDI — tarmoq navigatsiyani muzlatmasin.
    saveBozorDraftInBackground(widget.draft, WizardStep.description);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('description'),
        builder: (_) => BozorDescriptionStepScreen(draft: widget.draft),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Sutkalik narx ixtiyoriy — faqat asosiy narx talab qilinadi.
  bool get _isComplete => _p.amount.isNotEmpty;

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
                        title: tr(l, 'bozor.price.title'),
                        subtitle:
                            '${draft.stepNumber(WizardStep.price)}/${draft.stepCount}',
                        onBack: () => closeBozorWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: draft.stepCount,
                        activeIndex: draft.stepIndex(WizardStep.price),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          PriceField(
                            // Ijarada «Ijara haqi», sotuvda mulk turiga mos
                            // sarlavha («Kvartira narxi», «Uy narxi»…).
                            label: (draft.type ?? PropertyType.apartment)
                                .priceLabel(l, draft.deal),
                            controller: _amount,
                            unit: _p.unit,
                            required: true,
                            onPickUnit: () => _pickUnit(daily: false),
                          ),
                          const SizedBox(height: 12),
                          WizardSwitchTile(
                            label: tr(l, 'bozor.price.negotiable'),
                            value: _p.negotiable,
                            onChanged: (v) =>
                                setState(() => _p.negotiable = v),
                          ),
                          if (_isSale) ...[
                            const SizedBox(height: 12),
                            WizardSwitchTile(
                              label: tr(l, 'bozor.price.mortgage'),
                              value: _p.mortgage,
                              onChanged: (v) =>
                                  setState(() => _p.mortgage = v),
                            ),
                          ],
                          if (_hasDailyPrice) ...[
                            const SizedBox(height: 12),
                            PriceField(
                              label: tr(l, 'bozor.price.daily'),
                              controller: _daily,
                              unit: _p.dailyUnit,
                              onPickUnit: () => _pickUnit(daily: true),
                            ),
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
                        onContinue: _openDescription,
                        onBlockedTap: () => AppToast.error(
                          context,
                          tr(l, 'bozor.common.fill_required'),
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
