import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final locale = localeNotifier.value;
    final v = await _showPicker(
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
      title: _ScanMetadataStrings.pickTumanTitle(locale),
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
        final extra = [
          ?_tuman,
          ?_viloyat,
        ].join(', ');
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
                            placeholder:
                                _ScanMetadataStrings.pickViloyatTitle(locale),
                            value: _viloyat,
                            onTap: _pickViloyat,
                          ),
                          const SizedBox(height: 10),
                          _PickerField(
                            placeholder:
                                _ScanMetadataStrings.pickTumanTitle(locale),
                            value: _tuman,
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
                                : _ScanMetadataStrings
                                    .submitToSpecialist(locale),
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
      ('Kadastr raqami', draft.cadastreNumber),
      ('Obyekt turi', draft.objectType?.label ?? '—'),
      ('Skan', draft.scanCompleted ? 'Tayyor' : 'Kutilmoqda'),
      if (draft.hasLocation)
        (
          'Xarita',
          'lat: ${draft.latitude!.toStringAsFixed(6)}, '
              'lon: ${draft.longitude!.toStringAsFixed(6)}',
        ),
      if (tz != null) ...[
        ('Buyurtmachi', tz.customerName),
        if (tz.tin.trim().isNotEmpty) ('STIR', tz.tin),
        ('Telefon', tz.phone),
        if (tz.email.trim().isNotEmpty) ('E-mail', tz.email),
        if (tz.objectName.trim().isNotEmpty) ('Obyekt nomi', tz.objectName),
        if (tz.objectType != null)
          ('Loyiha turi', _objectTypeLabel(tz.objectType!, locale)),
        (
          'Qurilish turi',
          tz.constructionType.apiValue == 'rekonstruksiya'
              ? 'Rekonstruksiya'
              : 'Yangi qurilish',
        ),
        if (tz.floors != null) ('Qavatlar', '${tz.floors}'),
        if (tz.totalAreaSqm != null)
          ('Umumiy maydon', '${tz.totalAreaSqm} m²'),
        if (tz.buildingAreaSqm != null)
          ('Qurilish maydoni', '${tz.buildingAreaSqm} m²'),
        if (tz.maxHeightM != null) ('Balandlik', '${tz.maxHeightM} m'),
        if (tz.rooms.isNotEmpty)
          ('Xonalar', '${tz.rooms.length} ta'),
        if (tz.architecture.style != null)
          ('Uslub', tz.architecture.style!),
        if (tz.timeline.sketchDays != null)
          ('Eskiz loyiha', '${tz.timeline.sketchDays} kun'),
        if (tz.timeline.workingDays != null)
          ('Ishchi loyiha', '${tz.timeline.workingDays} kun'),
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
  static String appBarTitle(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Регион и сводка',
        'en' => 'Region & summary',
        _ => 'Hudud va xulosa',
      };

  static String appBarSubtitle(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Укажите регион и проверьте данные',
        'en' => 'Select the region and review the data',
        _ => 'Hududni tanlang va ma\'lumotlarni tekshiring',
      };

  static String sectionRegion(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Регион',
        'en' => 'Region',
        _ => 'Hudud',
      };

  static String sectionSummary(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Сводка',
        'en' => 'Summary',
        _ => 'Xulosa',
      };

  static String pickViloyatTitle(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Выберите регион',
        'en' => 'Select region',
        _ => 'Viloyatni tanlang',
      };

  static String pickTumanTitle(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Выберите район',
        'en' => 'Select district',
        _ => 'Tumanni tanlang',
      };

  static String tumanListSoon(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Список районов появится позже',
        'en' => 'District list will be available soon',
        _ => 'Tumanlar ro\'yxati keyinroq qo\'shiladi',
      };

  static String tzIncomplete(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Заявка ТЗ не заполнена',
        'en' => 'TZ form is incomplete',
        _ => 'TZ so\'rovnomasi to\'liq emas',
      };

  static String loginRequired(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Сначала войдите в аккаунт',
        'en' => 'Please log in first',
        _ => 'Avval tizimga kiring',
      };

  static String networkError(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Ошибка сети',
        'en' => 'Network error',
        _ => 'Tarmoq xatosi',
      };

  static String aiValuationStarted(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'AI-оценка скоро будет подключена',
        'en' => 'AI valuation will be connected soon',
        _ => 'AI baholash yaqinda ulanadi',
      };

  static String submitToSpecialist(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'Отправить специалисту',
        'en' => 'Submit to specialist',
        _ => 'Mutaxassisga yuborish',
      };

  static String aiValuationButton(Locale locale) =>
      switch (locale.languageCode) {
        'ru' => 'AI оценка',
        'en' => 'AI valuation',
        _ => 'AI baholash',
      };

  static String sending(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Отправка...',
        'en' => 'Sending...',
        _ => 'Yuborilmoqda...',
      };
}
