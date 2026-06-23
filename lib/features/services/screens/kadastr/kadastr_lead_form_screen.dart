/// Kadastr combined calculator — step 4: the lead form.
///
/// Collects contact details (ism / telefon / manzil) and submits ONE combined
/// application carrying all selected services + the taxminiy total. Reuses the
/// existing `POST /services/calculator/orders` endpoint (contact + per-service
/// lines are encoded into the order lines) — no backend change.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../auth/widgets/login_required_sheet.dart';
import '../../../../widgets/uz_phone_mask_formatter.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_calculator_order_service.dart';
import '../../models/calculator_draft.dart';
import '../../models/kadastr_estimate.dart';
import '../../widgets/service_app_bar.dart';
import '../calculator/arxitektura_tz_success_screen.dart';

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

  final _orders = CalculatorOrderApiService();
  bool _submitting = false;

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
    _orders.dispose();
    super.dispose();
  }

  /// National digits typed after the fixed +998 prefix (the controller holds
  /// only the "XX XXX XX XX" part; the formatter caps it at 9 digits).
  int get _phoneDigits =>
      _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').length;

  bool get _nameValid => _nameCtrl.text.trim().length >= 2;
  bool get _phoneValid => _phoneDigits == 9;
  bool get _valid => _nameValid && _phoneValid;

  /// Full E.164-ish number for the order: "+998 XX XXX XX XX".
  String get _fullPhone => '+998 ${_phoneCtrl.text.trim()}';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  CalculatorResult _buildOrder(Locale l) {
    final name = _nameCtrl.text.trim();
    final phone = _fullPhone;
    final address = _addressCtrl.text.trim();
    final n = widget.estimates.length;

    final lines = <CalculatorLine>[
      CalculatorLine(_S.name(l), name),
      CalculatorLine(_S.phone(l), phone),
      if (address.isNotEmpty) CalculatorLine(_S.address(l), address),
      CalculatorLine(_S.area(l), '${_fmtArea(widget.areaM2)} m²'),
      for (final e in widget.estimates)
        CalculatorLine(
          e.category.title(l),
          e.isQuote
              ? kadastrQuoteLabel(l)
              : fmtUzsPublic(l, e.totalUzs),
        ),
    ];

    return CalculatorResult(
      categoryTitle: _S.orderTitle(l, n),
      totalUzs: widget.totalUzs,
      note: _S.approxNote(l),
      lines: lines,
    );
  }

  Future<void> _submit() async {
    if (_submitting || !_valid) return;
    final l = Localizations.localeOf(context);
    if (!await ensureLoggedIn(context)) return;
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      final id = await _orders.submit(result: _buildOrder(l), token: token);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ArxitekturaTzSuccessScreen(orderId: id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack(_S.sendError(l, '$e'));
    }
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
                    label: _submitting ? _S.sending(l) : _S.send(l),
                    enabled: _valid && !_submitting,
                    onTap: _submit,
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
            prefixText: prefixText,
            prefixStyle: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 15,
              color: textColor,
            ),
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

String _fmtArea(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

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

  static String address(Locale l) =>
      _pick(l, 'Manzil', 'Адрес', 'Address');

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

  static String area(Locale l) => _pick(l, 'Maydon', 'Площадь', 'Area');

  static String orderTitle(Locale l, int n) =>
      _pick(l, 'Kadastr — $n xizmat', 'Кадастр — $n услуг', 'Cadastre — $n services');

  static String approxNote(Locale l) => _pick(
        l,
        'QQS bilan · taxminiy narx',
        'С НДС · примерная цена',
        'incl. VAT · approximate',
      );

  static String privacyHint(Locale l) => _pick(
        l,
        "Operatorimiz tez orada siz bilan bog'lanadi va aniq narxni aytadi.",
        'Наш оператор свяжется с вами и сообщит точную цену.',
        'Our operator will contact you shortly with the exact price.',
      );

  static String send(Locale l) =>
      _pick(l, 'Yuborish', 'Отправить', 'Submit');

  static String sending(Locale l) =>
      _pick(l, 'Yuborilmoqda...', 'Отправка...', 'Submitting...');

  static String sendError(Locale l, String e) => _pick(
        l,
        'Yuborishda xatolik: $e',
        'Ошибка отправки: $e',
        'Failed to send: $e',
      );
}
