/// Kadastr combined calculator — contact step for wizard-less selections.
///
/// Shown only when no Arxitektura/Dizayn wizard is selected (those collect
/// their own customer). Collects contact (ism / telefon / manzil) and pops a
/// [SharedApplicant]; the coordinator submits the simple services with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../../widgets/uz_phone_mask_formatter.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../models/calculator_draft.dart';
import '../../models/kadastr_applicant.dart';
import '../../models/kadastr_estimate.dart';
import '../../widgets/service_app_bar.dart';

class KadastrLeadFormScreen extends StatefulWidget {
  const KadastrLeadFormScreen({
    super.key,
    required this.areaM2,
    required this.estimates,
    required this.totalUzs,
  });

  final double areaM2;
  final List<KadastrServiceEstimate> estimates;
  final int totalUzs;

  @override
  State<KadastrLeadFormScreen> createState() => _KadastrLeadFormScreenState();
}

class _KadastrLeadFormScreenState extends State<KadastrLeadFormScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onChanged);
    _phoneCtrl.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  /// National digits typed after the fixed +998 prefix (the controller holds
  /// only the "XX XXX XX XX" part; the formatter caps it at 9 digits).
  int get _phoneDigits =>
      _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').length;

  bool get _nameValid => _nameCtrl.text.trim().length >= 2;
  bool get _phoneValid => _phoneDigits == 9;
  bool get _valid => _nameValid && _phoneValid;

  void _continue() {
    if (!_valid) return;
    Navigator.of(context).pop(
      SharedApplicant(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(), // national digits; fullPhone adds +998
        address: _addressCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

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
                  child: ServiceAppBar(title: _S.appBar(l)),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      _SummaryCard(
                        estimates: widget.estimates,
                        totalUzs: widget.totalUzs,
                        locale: l,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _S.contact(l),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: headingColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        label: _S.name(l),
                        hint: _S.nameHint(l),
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        label: _S.phone(l),
                        hint: '90 123-45-67',
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        prefixText: '+998 ',
                        inputFormatters: const [UzPhoneMaskFormatter()],
                        errorText:
                            (_phoneCtrl.text.trim().isNotEmpty && !_phoneValid)
                                ? _S.phoneError(l)
                                : null,
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        label: _S.addressOptional(l),
                        hint: _S.addressHint(l),
                        controller: _addressCtrl,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _S.privacyHint(l),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 12,
                          height: 1.4,
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _S.send(l),
                    enabled: _valid,
                    onTap: _continue,
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.estimates,
    required this.totalUzs,
    required this.locale,
  });

  final List<KadastrServiceEstimate> estimates;
  final int totalUzs;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _S.servicesLabel(locale),
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12.5,
              color: subColor,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in estimates)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: e.category.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    e.category.title(locale),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: e.category.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  _S.totalLabel(locale),
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    color: subColor,
                  ),
                ),
              ),
              Text(
                fmtUzsPublic(locale, totalUzs),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: titleColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.errorText,
    this.prefixText,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF6C7278);
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);
    const danger = Color(0xFFE5484D);
    final hasError = errorText != null;

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
              color: labelColor,
            ),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 15,
            color: textColor,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            // prefixIcon (not prefixText) so the +998 stays visible even when
            // the field is empty and unfocused.
            prefixIcon: prefixText == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 14, right: 2),
                    child: Text(
                      prefixText!,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                  ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              color: hintColor,
            ),
            filled: true,
            fillColor: fill,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hasError ? danger : border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: hasError ? danger : AppColors.splashGreen,
                width: 1.4,
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              errorText!,
              style: const TextStyle(
                fontFamily: 'MTSText',
                fontSize: 12,
                color: danger,
              ),
            ),
          ),
      ],
    );
  }
}

class _S {
  const _S._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  static String appBar(Locale l) => _pick(l, 'Ariza', 'Заявка', 'Application');

  static String servicesLabel(Locale l) =>
      _pick(l, 'Tanlangan xizmatlar', 'Выбранные услуги', 'Selected services');

  static String totalLabel(Locale l) =>
      _pick(l, 'Taxminiy jami', 'Примерно итого', 'Estimated total');

  static String contact(Locale l) =>
      _pick(l, "Bog'lanish ma'lumotlari", 'Контактные данные', 'Contact details');

  static String name(Locale l) => _pick(l, 'Ism', 'Имя', 'Name');

  static String nameHint(Locale l) =>
      _pick(l, 'Ism familiya', 'Имя и фамилия', 'Full name');

  static String phone(Locale l) => _pick(l, 'Telefon', 'Телефон', 'Phone');

  static String phoneError(Locale l) => _pick(
        l,
        "To'g'ri telefon raqamini kiriting",
        'Введите корректный номер телефона',
        'Enter a valid phone number',
      );

  static String addressOptional(Locale l) => _pick(
        l,
        'Manzil (ixtiyoriy)',
        'Адрес (необязательно)',
        'Address (optional)',
      );

  static String addressHint(Locale l) => _pick(
        l,
        'Shahar, tuman, manzil',
        'Город, район, адрес',
        'City, district, address',
      );

  static String privacyHint(Locale l) => _pick(
        l,
        "Operatorimiz tez orada siz bilan bog'lanadi va aniq narxni aytadi.",
        'Наш оператор свяжется с вами и сообщит точную цену.',
        'Our operator will contact you shortly with the exact price.',
      );

  static String send(Locale l) =>
      _pick(l, 'Yuborish', 'Отправить', 'Submit');
}
