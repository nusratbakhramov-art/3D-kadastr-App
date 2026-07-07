import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../api_architecture_order_service.dart';
import '../models/architecture_order_draft.dart';
import '../models/scan_draft.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'calculator/arxitektura_tz_success_screen.dart';

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

const _geoLabels = <String, ({String ru, String en})>{
  'Toshkent shahri': (ru: 'Ташкент', en: 'Tashkent city'),
  'Toshkent viloyati': (ru: 'Ташкентская область', en: 'Tashkent region'),
  'Andijon': (ru: 'Андижан', en: 'Andijan'),
  'Buxoro': (ru: 'Бухара', en: 'Bukhara'),
  'Farg\'ona': (ru: 'Фергана', en: 'Fergana'),
  'Jizzax': (ru: 'Джизак', en: 'Jizzakh'),
  'Namangan': (ru: 'Наманган', en: 'Namangan'),
  'Navoiy': (ru: 'Навои', en: 'Navoi'),
  'Qashqadaryo': (ru: 'Кашкадарья', en: 'Kashkadarya'),
  'Qoraqalpog\'iston': (ru: 'Каракалпакстан', en: 'Karakalpakstan'),
  'Samarqand': (ru: 'Самарканд', en: 'Samarkand'),
  'Sirdaryo': (ru: 'Сырдарья', en: 'Syrdarya'),
  'Surxondaryo': (ru: 'Сурхандарья', en: 'Surkhandarya'),
  'Xorazm': (ru: 'Хорезм', en: 'Khorezm'),
  'Bektemir': (ru: 'Бектемир', en: 'Bektemir'),
  'Chilonzor': (ru: 'Чиланзар', en: 'Chilanzar'),
  'Mirobod': (ru: 'Мирабад', en: 'Mirabad'),
  'Mirzo Ulug\'bek': (ru: 'Мирзо-Улугбек', en: 'Mirzo Ulugbek'),
  'Olmazor': (ru: 'Алмазар', en: 'Almazar'),
  'Sirg\'ali': (ru: 'Сергелийский', en: 'Sergeli'),
  'Shayxontohur': (ru: 'Шайхантахур', en: 'Shaykhantakhur'),
  'Uchtepa': (ru: 'Учтепа', en: 'Uchtepa'),
  'Yakkasaroy': (ru: 'Яккасарай', en: 'Yakkasaray'),
  'Yashnobod': (ru: 'Яшнабад', en: 'Yashnabad'),
  'Yunusobod': (ru: 'Юнусабад', en: 'Yunusabad'),
  'Bekobod': (ru: 'Бекабад', en: 'Bekabad'),
  'Bo\'ka': (ru: 'Бука', en: 'Buka'),
  'Chinoz': (ru: 'Чиназ', en: 'Chinaz'),
  'Ohangaron': (ru: 'Ахангаран', en: 'Ohangaron'),
  'Olmaliq': (ru: 'Алмалык', en: 'Almalyk'),
  'Parkent': (ru: 'Паркент', en: 'Parkent'),
  'Piskent': (ru: 'Пскент', en: 'Pskent'),
  'Quyichirchiq': (ru: 'Куйичирчик', en: 'Quyichirchiq'),
  'O\'rtachirchiq': (ru: 'Уртачирчик', en: 'Ortachirchiq'),
  'Yangiyo\'l': (ru: 'Янгиюль', en: 'Yangiyul'),
  'Zangiota': (ru: 'Зангиата', en: 'Zangiota'),
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

  String _localizedGeoName(String value, Locale locale) {
    final label = _geoLabels[value];
    if (label == null) return value;
    return switch (locale.languageCode) {
      'ru' => label.ru,
      'en' => label.en,
      _ => value,
    };
  }

  Future<void> _pickViloyat() async {
    final locale = localeNotifier.value;
    final v = await _showPicker(
      locale: locale,
      title: _ScanMetadataStrings.pickViloyatTitle(locale),
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
    final locale = localeNotifier.value;
    final options = _tumanlarByViloyat[_viloyat!] ?? const <String>[];
    if (options.isEmpty) {
      AppToast.error(context, _ScanMetadataStrings.tumanListSoon(locale));
      return;
    }
    final t = await _showPicker(
      locale: locale,
      title: _ScanMetadataStrings.pickTumanTitle(locale),
      options: options,
      current: _tuman,
    );
    if (t == null || !mounted) return;
    setState(() => _tuman = t);
  }

  Future<String?> _showPicker({
    required Locale locale,
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
                                  _localizedGeoName(value, locale),
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

  bool _submitting = false;

  Future<void> _submitToSpecialist() async {
    if (!_ready || _submitting) return;
    HapticFeedback.lightImpact();
    final locale = localeNotifier.value;

    final tz = widget.draft.tzDraft;
    if (tz == null || !tz.canSubmit) {
      AppToast.error(context, _ScanMetadataStrings.tzIncomplete(locale));
      return;
    }

    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null) {
      if (!mounted) return;
      AppToast.error(context, _ScanMetadataStrings.loginRequired(locale));
      return;
    }

    setState(() => _submitting = true);
    try {
      // Hudud qo'lda tanlangan bo'lsa, TZ draft'ga ham qo'shamiz
      // (backend `address` matni sifatida).
      final enrichedTz = tz;
      if (_viloyat != null || _tuman != null) {
        final extra = [?_tuman, ?_viloyat].join(', ');
        if (enrichedTz.address.trim().isEmpty) {
          enrichedTz.address = extra;
        } else {
          enrichedTz.address = '${enrichedTz.address} ($extra)';
        }
      }

      final api = ArchitectureOrderApiService();
      final created = await api.submit(draft: enrichedTz, token: token);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ArxitekturaTzSuccessScreen(orderId: created.id),
        ),
      );
    } on ArchitectureOrderApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (e) {
      if (mounted) {
        AppToast.error(
          context,
          '${_ScanMetadataStrings.networkError(locale)}: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _submitForAiValuation() {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    // TODO: AI baholash flow'iga ulash (yangi ekran).
    AppToast.success(
      context,
      _ScanMetadataStrings.aiValuationStarted(localeNotifier.value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => _build(context, locale),
    );
  }

  Widget _build(BuildContext context, Locale locale) {
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
                      child: ServiceAppBar(
                        title: _ScanMetadataStrings.appBarTitle(locale),
                        subtitle: _ScanMetadataStrings.appBarSubtitle(locale),
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
                          _SectionLabel(
                            _ScanMetadataStrings.sectionRegion(locale),
                            color: labelColor,
                          ),
                          const SizedBox(height: 10),
                          _PickerField(
                            placeholder: _ScanMetadataStrings.pickViloyatTitle(
                              locale,
                            ),
                            value: _viloyat,
                            displayValue: _viloyat == null
                                ? null
                                : _localizedGeoName(_viloyat!, locale),
                            onTap: _pickViloyat,
                          ),
                          const SizedBox(height: 10),
                          _PickerField(
                            placeholder: _ScanMetadataStrings.pickTumanTitle(
                              locale,
                            ),
                            value: _tuman,
                            displayValue: _tuman == null
                                ? null
                                : _localizedGeoName(_tuman!, locale),
                            onTap: _viloyat == null ? null : _pickTuman,
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(
                            _ScanMetadataStrings.sectionSummary(locale),
                            color: labelColor,
                          ),
                          const SizedBox(height: 10),
                          _SummaryCard(draft: widget.draft, locale: locale),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListingCtaButton(
                            label: _submitting
                                ? _ScanMetadataStrings.sending(locale)
                                : _ScanMetadataStrings.submitToSpecialist(
                                    locale,
                                  ),
                            enabled: _ready && !_submitting,
                            onTap: _submitToSpecialist,
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _ready && !_submitting
                                ? _submitForAiValuation
                                : null,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              side: const BorderSide(
                                color: AppColors.splashGreen,
                                width: 1.4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: Text(
                              _ScanMetadataStrings.aiValuationButton(locale),
                              style: const TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.splashGreen,
                              ),
                            ),
                          ),
                        ],
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
    required this.displayValue,
    required this.onTap,
  });

  final String placeholder;
  final String? value;
  final String? displayValue;
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
                  displayValue ?? placeholder,
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

String _objectTypeLabel(ArchObjectType t, Locale locale) =>
    switch (locale.languageCode) {
      'ru' => switch (t) {
        ArchObjectType.yakkaSmall => 'Частный дом <500 м²',
        ArchObjectType.yakkaLarge => 'Частный дом >500 м²',
        ArchObjectType.kopQavatli => 'Многоквартирный дом',
        ArchObjectType.ofis => 'Офис',
        ArchObjectType.savdoMarkazi => 'Торговый центр',
        ArchObjectType.mehmonxona => 'Гостиница',
        ArchObjectType.sanoat => 'Промышленный',
        ArchObjectType.omborxona => 'Склад',
        ArchObjectType.boshqa => 'Другое',
      },
      'en' => switch (t) {
        ArchObjectType.yakkaSmall => 'Single house <500 m²',
        ArchObjectType.yakkaLarge => 'Single house >500 m²',
        ArchObjectType.kopQavatli => 'Multi-family residence',
        ArchObjectType.ofis => 'Office',
        ArchObjectType.savdoMarkazi => 'Shopping mall',
        ArchObjectType.mehmonxona => 'Hotel',
        ArchObjectType.sanoat => 'Industrial',
        ArchObjectType.omborxona => 'Warehouse',
        ArchObjectType.boshqa => 'Other',
      },
      _ => switch (t) {
        ArchObjectType.yakkaSmall => 'Yakka uy <500 m²',
        ArchObjectType.yakkaLarge => 'Yakka uy >500 m²',
        ArchObjectType.kopQavatli => 'Ko\'p qavatli turar-joy',
        ArchObjectType.ofis => 'Ofis',
        ArchObjectType.savdoMarkazi => 'Savdo markazi',
        ArchObjectType.mehmonxona => 'Mehmonxona',
        ArchObjectType.sanoat => 'Sanoat',
        ArchObjectType.omborxona => 'Omborxona',
        ArchObjectType.boshqa => 'Boshqa',
      },
    };

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.draft, required this.locale});

  final ScanDraft draft;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    final tz = draft.tzDraft;
    final rows = <(String, String)>[
      (_ScanMetadataStrings.rowCadastreNumber(locale), draft.cadastreNumber),
      (
        _ScanMetadataStrings.rowObjectType(locale),
        draft.objectType?.localizedLabel(locale) ?? '—',
      ),
      (
        _ScanMetadataStrings.rowScan(locale),
        draft.scanCompleted
            ? _ScanMetadataStrings.scanReady(locale)
            : _ScanMetadataStrings.scanPending(locale),
      ),
      if (draft.hasLocation)
        (
          _ScanMetadataStrings.rowMap(locale),
          'lat: ${draft.latitude!.toStringAsFixed(6)}, '
              'lon: ${draft.longitude!.toStringAsFixed(6)}',
        ),
      if (tz != null) ...[
        (_ScanMetadataStrings.rowCustomer(locale), tz.customerName),
        if (tz.tin.trim().isNotEmpty)
          (_ScanMetadataStrings.rowTin(locale), tz.tin),
        (_ScanMetadataStrings.rowPhone(locale), tz.phone),
        if (tz.email.trim().isNotEmpty)
          (_ScanMetadataStrings.rowEmail(locale), tz.email),
        if (tz.objectName.trim().isNotEmpty)
          (_ScanMetadataStrings.rowObjectName(locale), tz.objectName),
        if (tz.objectType != null)
          (
            _ScanMetadataStrings.rowProjectType(locale),
            _objectTypeLabel(tz.objectType!, locale),
          ),
        (
          _ScanMetadataStrings.rowConstructionType(locale),
          tz.constructionType.apiValue == 'rekonstruksiya'
              ? _ScanMetadataStrings.constructionReconstruction(locale)
              : _ScanMetadataStrings.constructionNew(locale),
        ),
        if (tz.floors != null)
          (_ScanMetadataStrings.rowFloors(locale), '${tz.floors}'),
        if (tz.totalAreaSqm != null)
          (_ScanMetadataStrings.rowTotalArea(locale), '${tz.totalAreaSqm} m²'),
        if (tz.buildingAreaSqm != null)
          (
            _ScanMetadataStrings.rowBuildingArea(locale),
            '${tz.buildingAreaSqm} m²',
          ),
        if (tz.maxHeightM != null)
          (_ScanMetadataStrings.rowHeight(locale), '${tz.maxHeightM} m'),
        if (tz.rooms.isNotEmpty)
          (
            _ScanMetadataStrings.rowRooms(locale),
            _ScanMetadataStrings.roomsValue(locale, tz.rooms.length),
          ),
        if (tz.architecture.style != null)
          (_ScanMetadataStrings.rowStyle(locale), tz.architecture.style!),
        if (tz.timeline.sketchDays != null)
          (
            _ScanMetadataStrings.rowSketchProject(locale),
            _ScanMetadataStrings.daysValue(locale, tz.timeline.sketchDays!),
          ),
        if (tz.timeline.workingDays != null)
          (
            _ScanMetadataStrings.rowWorkingProject(locale),
            _ScanMetadataStrings.daysValue(locale, tz.timeline.workingDays!),
          ),
      ],
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

class _ScanMetadataStrings {
  static String _t(
    Locale locale,
    String key,
    String uz,
    String ru,
    String en,
  ) => tr(locale, key, uz: uz, ru: ru, en: en);

  static String appBarTitle(Locale locale) => _t(
    locale,
    'scan.metadata.app_bar_title',
    'Hudud va xulosa',
    'Регион и сводка',
    'Region & summary',
  );
  static String appBarSubtitle(Locale locale) => _t(
    locale,
    'scan.metadata.app_bar_subtitle',
    'Hududni tanlang va ma\'lumotlarni tekshiring',
    'Укажите регион и проверьте данные',
    'Select the region and review the data',
  );
  static String sectionRegion(Locale locale) =>
      _t(locale, 'scan.metadata.section_region', 'Hudud', 'Регион', 'Region');
  static String sectionSummary(Locale locale) => _t(
    locale,
    'scan.metadata.section_summary',
    'Xulosa',
    'Сводка',
    'Summary',
  );
  static String pickViloyatTitle(Locale locale) => _t(
    locale,
    'scan.metadata.pick_viloyat_title',
    'Viloyatni tanlang',
    'Выберите регион',
    'Select region',
  );
  static String pickTumanTitle(Locale locale) => _t(
    locale,
    'scan.metadata.pick_tuman_title',
    'Tumanni tanlang',
    'Выберите район',
    'Select district',
  );
  static String tumanListSoon(Locale locale) => _t(
    locale,
    'scan.metadata.tuman_list_soon',
    'Tumanlar ro\'yxati keyinroq qo\'shiladi',
    'Список районов появится позже',
    'District list will be available soon',
  );
  static String tzIncomplete(Locale locale) => _t(
    locale,
    'scan.metadata.tz_incomplete',
    'So\'rovnoma to\'liq emas',
    'Анкета не заполнена',
    'The form is incomplete',
  );
  static String loginRequired(Locale locale) => _t(
    locale,
    'scan.metadata.login_required',
    'Avval tizimga kiring',
    'Сначала войдите в аккаунт',
    'Please log in first',
  );
  static String networkError(Locale locale) => _t(
    locale,
    'scan.metadata.network_error',
    'Tarmoq xatosi',
    'Ошибка сети',
    'Network error',
  );
  static String aiValuationStarted(Locale locale) => _t(
    locale,
    'scan.metadata.ai_valuation_started',
    'AI baholash yaqinda ulanadi',
    'AI-оценка скоро будет подключена',
    'AI valuation will be connected soon',
  );
  static String submitToSpecialist(Locale locale) => _t(
    locale,
    'scan.metadata.submit_to_specialist',
    'Mutaxassisga yuborish',
    'Отправить специалисту',
    'Submit to specialist',
  );
  static String aiValuationButton(Locale locale) => _t(
    locale,
    'scan.metadata.ai_valuation_button',
    'AI baholash',
    'AI оценка',
    'AI valuation',
  );
  static String sending(Locale locale) => _t(
    locale,
    'scan.metadata.sending',
    'Yuborilmoqda...',
    'Отправка...',
    'Sending...',
  );
  static String rowCadastreNumber(Locale locale) => _t(
    locale,
    'scan.metadata.row_cadastre_number',
    'Kadastr raqami',
    'Кадастровый номер',
    'Cadastre number',
  );
  static String rowObjectType(Locale locale) => _t(
    locale,
    'scan.metadata.row_object_type',
    'Obyekt turi',
    'Тип объекта',
    'Object type',
  );
  static String rowScan(Locale locale) =>
      _t(locale, 'scan.metadata.row_scan', 'Skan', 'Скан', 'Scan');
  static String scanReady(Locale locale) =>
      _t(locale, 'scan.metadata.scan_ready', 'Tayyor', 'Готов', 'Ready');
  static String scanPending(Locale locale) => _t(
    locale,
    'scan.metadata.scan_pending',
    'Kutilmoqda',
    'Ожидается',
    'Pending',
  );
  static String rowMap(Locale locale) =>
      _t(locale, 'scan.metadata.row_map', 'Xarita', 'Карта', 'Map');
  static String rowCustomer(Locale locale) => _t(
    locale,
    'scan.metadata.row_customer',
    'Buyurtmachi',
    'Заказчик',
    'Customer',
  );
  static String rowTin(Locale locale) =>
      _t(locale, 'scan.metadata.row_tin', 'STIR', 'ИНН', 'TIN');
  static String rowPhone(Locale locale) =>
      _t(locale, 'scan.metadata.row_phone', 'Telefon', 'Телефон', 'Phone');
  static String rowEmail(Locale locale) =>
      _t(locale, 'scan.metadata.row_email', 'E-mail', 'E-mail', 'E-mail');
  static String rowObjectName(Locale locale) => _t(
    locale,
    'scan.metadata.row_object_name',
    'Obyekt nomi',
    'Название объекта',
    'Object name',
  );
  static String rowProjectType(Locale locale) => _t(
    locale,
    'scan.metadata.row_project_type',
    'Loyiha turi',
    'Тип проекта',
    'Project type',
  );
  static String rowConstructionType(Locale locale) => _t(
    locale,
    'scan.metadata.row_construction_type',
    'Qurilish turi',
    'Тип строительства',
    'Construction type',
  );
  static String constructionReconstruction(Locale locale) => _t(
    locale,
    'scan.metadata.construction_reconstruction',
    'Rekonstruksiya',
    'Реконструкция',
    'Reconstruction',
  );
  static String constructionNew(Locale locale) => _t(
    locale,
    'scan.metadata.construction_new',
    'Yangi qurilish',
    'Новое строительство',
    'New construction',
  );
  static String rowFloors(Locale locale) =>
      _t(locale, 'scan.metadata.row_floors', 'Qavatlar', 'Этажность', 'Floors');
  static String rowTotalArea(Locale locale) => _t(
    locale,
    'scan.metadata.row_total_area',
    'Umumiy maydon',
    'Общая площадь',
    'Total area',
  );
  static String rowBuildingArea(Locale locale) => _t(
    locale,
    'scan.metadata.row_building_area',
    'Qurilish maydoni',
    'Площадь застройки',
    'Building area',
  );
  static String rowHeight(Locale locale) =>
      _t(locale, 'scan.metadata.row_height', 'Balandlik', 'Высота', 'Height');
  static String rowRooms(Locale locale) =>
      _t(locale, 'scan.metadata.row_rooms', 'Xonalar', 'Помещения', 'Rooms');
  static String roomsValue(Locale locale, int count) => _t(
    locale,
    'scan.metadata.rooms_value',
    '$count ta',
    '$count шт.',
    '$count rooms',
  );
  static String rowStyle(Locale locale) =>
      _t(locale, 'scan.metadata.row_style', 'Uslub', 'Стиль', 'Style');
  static String rowSketchProject(Locale locale) => _t(
    locale,
    'scan.metadata.row_sketch_project',
    'Eskiz loyiha',
    'Эскизный проект',
    'Concept design',
  );
  static String rowWorkingProject(Locale locale) => _t(
    locale,
    'scan.metadata.row_working_project',
    'Ishchi loyiha',
    'Рабочий проект',
    'Working design',
  );
  static String daysValue(Locale locale, int days) => _t(
    locale,
    'scan.metadata.days_value',
    '$days kun',
    '$days дн.',
    '$days days',
  );
}
