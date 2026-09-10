/// "Bozor AI" sehrgarining 1-qadami — `Тип объявления`.
///
/// Uchta tanlov ketma-ket bog'langan:
///   e'lon turi → mulk toifasi → mulk turi
/// Oxirgisi butun qolgan oqimni belgilaydi (maydonlar VA qadamlar soni), shu
/// sababli u toifa tanlanmaguncha o'chiq turadi va toifa o'zgarsa tozalanadi.
///
/// Birinchi tanlov — e'lon turi — serverdagi `bozor_sale_enabled` bayrog'iga
/// bog'liq: sotuv sehrgari hali yarim (narx qadami ijara yorliqlarini beradi,
/// "Сделка" qadami yo'q), shuning uchun bayroq o'chiq bo'lsa "Продажа" umuman
/// taklif qilinmaydi.
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
import '../models/bozor_draft.dart';
import 'bozor_address_step_screen.dart';
import '../widgets/option_picker_sheet.dart';
import '../widgets/select_field.dart';

class BozorTypeStepScreen extends StatefulWidget {
  const BozorTypeStepScreen({super.key, this.draft, this.api});

  /// Oqimga qaytib kelinganda oldingi tanlov saqlanib qolsin.
  final BozorDraft? draft;

  /// Faqat testlar uchun — sotuv bayrog'ini o'qiydigan klientni almashtirish.
  final BozorApi? api;

  @override
  State<BozorTypeStepScreen> createState() => _BozorTypeStepScreenState();
}

class _BozorTypeStepScreenState extends State<BozorTypeStepScreen> {
  late final BozorDraft _draft = widget.draft ?? BozorDraft();
  late final BozorApi _api = widget.api ?? BozorApi();

  /// Sukut `false`: bayroq javobi kelmaguncha ham, tarmoq yo'q bo'lsa ham
  /// sotuv ko'rinmaydi. Yarim ishlaydigan oqimni ko'rsatgandan ko'ra
  /// ko'rsatmaslik arzon.
  bool _saleEnabled = false;
  bool _gateRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gateRequested) return;
    _gateRequested = true;
    // Til shu yerda mavjud (initState'da emas), bayroqning o'zi esa tilga
    // bog'liq emas — shuning uchun bir marta so'raladi.
    _loadSaleGate(Localizations.localeOf(context).languageCode);
  }

  @override
  void dispose() {
    // Klient testdan berilgan bo'lsa uni yopish testning ishi.
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  /// Bayroqni fonda o'qiydi. Ataylab `await` qilinmaydi va xato yutiladi:
  /// bu jimgina cheklov, foydalanuvchiga ko'rsatiladigan xato emas — aks holda
  /// offline foydalanuvchi sehrgarni umuman ocholmaydi.
  Future<void> _loadSaleGate(String locale) async {
    try {
      final ref = await _api.reference(locale);
      if (!mounted) return;
      _applyGate(ref.saleEnabled);
    } catch (_) {
      // Sukut `false` bo'lib qoladi — ijara oqimi ishlashda davom etadi.
      if (mounted) _applyGate(false);
    }
  }

  /// Bayroq javobi KELGANDAN keyin qo'llanadi.
  ///
  /// Nega bu yerda, `didChangeDependencies` da emas: o'sha payt `_saleEnabled`
  /// hamisha `false` bo'ladi (so'rov hali ketmagan), ya'ni pastdagi shart
  /// bayroqdan qat'i nazar ishga tushib, e'lon turini `rent` ga majburlab
  /// qo'yardi va bayroq `true` bo'lganda ham qaytarmasdi. Natijada sotuv
  /// yoqilganda 1-qadam «В аренду» bilan to'lgan holda ochilib, sotuvchi
  /// sezmasdan ijara e'loni yaratishi mumkin edi.
  void _applyGate(bool saleEnabled) {
    setState(() {
      _saleEnabled = saleEnabled;
      // Bayroq o'chiq — pickerda yakka variant qoladi, shuning uchun uni
      // oldindan qo'yamiz: maydon bo'sh turib "Далее" ni bloklamasin va
      // qoralamada yopiq `sale` qolib ketmasin. Bayroq YOQIQ bo'lsa tanlovni
      // foydalanuvchi qiladi — biz hech narsani to'ldirmaymiz.
      if (!saleEnabled && _draft.deal != DealType.rent) {
        _draft.deal = DealType.rent;
      }
    });
  }

  /// Pickerda ko'rinadigan e'lon turlari. Bayroq o'chiq bo'lsa bitta element
  /// qoladi — varaq shunda ham ochiladi va ishlaydi.
  List<DealType> get _dealOptions =>
      _saleEnabled ? DealType.values : const [DealType.rent];

  Future<void> _pickDeal() async {
    final l = Localizations.localeOf(context);
    final picked = await showOptionPickerSheet<DealType>(
      context,
      title: _S.dealLabel(l),
      options: _dealOptions,
      labelOf: (v) => v.label(l),
      selected: _draft.deal,
    );
    if (picked == null || !mounted) return;
    setState(() => _draft.deal = picked);
  }

  Future<void> _pickKind() async {
    final l = Localizations.localeOf(context);
    final picked = await showOptionPickerSheet<PropertyKind>(
      context,
      title: _S.kindLabel(l),
      options: PropertyKind.values,
      labelOf: (v) => v.label(l),
      selected: _draft.kind,
    );
    if (picked == null || !mounted) return;
    // Toifa o'zgarsa unga tegishli bo'lmagan tur tozalanadi — aks holda
    // "Noturar joy + Kvartira" kabi imkonsiz juftlik qolib ketardi.
    setState(() => _draft.setKind(picked));
  }

  Future<void> _pickType() async {
    final kind = _draft.kind;
    if (kind == null) return;
    final l = Localizations.localeOf(context);
    final picked = await showOptionPickerSheet<PropertyType>(
      context,
      title: _S.typeLabel(l),
      options: kind.types,
      labelOf: (v) => v.label(l),
      selected: _draft.type,
    );
    if (picked == null || !mounted) return;
    setState(() => _draft.setType(picked));
  }

  void _onBlocked() {
    final l = Localizations.localeOf(context);
    AppToast.error(context, _S.fillAll(l));
  }

  Future<void> _onContinue() async {
    // Qoralamani fonda saqlaymiz: foydalanuvchi shu qadamda chiqib
    // ketsa "Mening e'lonlarim" dan aynan shu joydan davom etadi.
    // `await` QILINMAYDI — tarmoq navigatsiyani muzlatmasin.
    saveBozorDraftInBackground(_draft, WizardStep.address);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('address'),
        builder: (_) => BozorAddressStepScreen(draft: _draft),
      ),
    );
    // Orqaga qaytilganda progress/qadam soni qoralamaga qarab qayta chizilsin.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final kind = _draft.kind;

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
                        title: _S.stepTitle(l),
                        // Qadamlar soni tanlangan mulk turiga bog'liq: "Boshqa
                        // noturar joy" da 6 ta qadam bo'ladi, qolganida 7 ta.
                        subtitle: '${_draft.stepNumber(WizardStep.type)}'
                            '/${_draft.stepCount}',
                        onBack: () => closeBozorWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: _draft.stepCount,
                        activeIndex: _draft.stepIndex(WizardStep.type),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          SelectField(
                            label: _S.dealLabel(l),
                            value: _draft.deal?.label(l),
                            placeholder: _S.choose(l),
                            onTap: _pickDeal,
                          ),
                          const SizedBox(height: 12),
                          SelectField(
                            label: _S.kindLabel(l),
                            value: _draft.kind?.label(l),
                            placeholder: _S.choose(l),
                            onTap: _pickKind,
                          ),
                          const SizedBox(height: 12),
                          SelectField(
                            label: _S.typeLabel(l),
                            value: _draft.type?.label(l),
                            // Toifa tanlanmaguncha ro'yxatda nima
                            // ko'rsatishni bilmaymiz — qator o'chiq turadi.
                            placeholder: kind == null
                                ? _S.chooseKindFirst(l)
                                : _S.choose(l),
                            enabled: kind != null,
                            onTap: _pickType,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: WizardNavBar(
                        continueLabel: _S.next(l),
                        continueEnabled: _draft.isTypeStepComplete,
                        onContinue: _onContinue,
                        onBlockedTap: _onBlocked,
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

class _S {
  const _S._();

  static String stepTitle(Locale l) => tr(l, 'bozor.step.type.title');
  static String dealLabel(Locale l) => tr(l, 'bozor.field.deal_type');
  static String kindLabel(Locale l) => tr(l, 'bozor.field.property_kind');
  static String typeLabel(Locale l) => tr(l, 'bozor.field.property_type');
  static String choose(Locale l) => tr(l, 'bozor.common.choose');
  static String chooseKindFirst(Locale l) =>
      tr(l, 'bozor.common.choose_kind_first');
  static String next(Locale l) => tr(l, 'bozor.common.next');
  static String fillAll(Locale l) => tr(l, 'bozor.common.fill_all');
}
