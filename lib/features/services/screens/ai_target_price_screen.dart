/// AI Baholash — natijadan keyingi qadam: foydalanuvchidan MAQSADLI sotuv
/// narxini so'raydi ("Qaysi narxda sotmoqchisiz?").
///
/// Ixtiyoriy — foydalanuvchi bo'sh qoldirib davom etishi mumkin. Kiritilgan
/// qiymat arizaga biriktiriladi (`PATCH /ai-valuations/{id}/target-price`), shu
/// bois baholash guruhi egasi qancha so'rayotganini ko'radi. Keyin appraiser
/// hujjatlari (credentials) → to'lov oqimiga o'tadi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../api_ai_valuation_job_service.dart';
import '../models/calculator_draft.dart' show fmtUzsPublic;
import '../widgets/service_app_bar.dart';
import 'ai_credentials_screen.dart';

class AiTargetPriceScreen extends StatefulWidget {
  const AiTargetPriceScreen({
    super.key,
    required this.jobId,
    this.estimatedValue,
  });

  /// AI valuation job id — narx shu arizaga biriktiriladi.
  final int jobId;

  /// AI hisoblagan taxminiy qiymat (so'm) — anchor sifatida ko'rsatiladi.
  final double? estimatedValue;

  @override
  State<AiTargetPriceScreen> createState() => _AiTargetPriceScreenState();
}

class _AiTargetPriceScreenState extends State<AiTargetPriceScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final TextEditingController _areaCtrl = TextEditingController();
  final AiValuationJobService _api = AiValuationJobService();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _areaCtrl.dispose();
    _api.dispose();
    super.dispose();
  }

  double? get _enteredPrice {
    final digits = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  double? get _enteredArea {
    final t = _areaCtrl.text.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _continue() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l = Localizations.localeOf(context);
    final price = _enteredPrice;
    final area = _enteredArea;
    if (price != null || area != null) {
      try {
        final session = await const AuthStorage().loadSession();
        final token = session.token;
        if (token != null && token.isNotEmpty) {
          await _api.setTargetPrice(
            jobId: widget.jobId,
            price: price,
            areaM2: area,
            token: token,
          );
        }
      } catch (_) {
        // Narx ixtiyoriy — saqlash uzilsa ham oqimni bloklamaymiz, faqat
        // ogohlantiramiz va davom etamiz.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_S.saveFailed(l))),
          );
        }
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    // Natija → (ixtiyoriy) narx → baholovchi hujjatlari → to'lov.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiCredentialsScreen(referenceId: widget.jobId),
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
                  child: ServiceAppBar(
                    title: _S.appBar(l),
                    subtitle: _S.appBarSub(l),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      Text(
                        _S.heading(l),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          height: 1.2,
                          color: headingColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _S.subheading(l),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 13,
                          height: 1.4,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _AmountField(
                        controller: _ctrl,
                        isDark: isDark,
                        locale: l,
                        suffix: _S.soum(l),
                        autofocus: true,
                        inputFormatters: const [_MoneyInputFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                      if (widget.estimatedValue != null) ...[
                        const SizedBox(height: 14),
                        _EstimateHint(
                          value: widget.estimatedValue!,
                          isDark: isDark,
                          locale: l,
                        ),
                      ],
                      const SizedBox(height: 22),
                      Text(
                        _S.areaLabel(l),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: headingColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _AmountField(
                        controller: _areaCtrl,
                        isDark: isDark,
                        locale: l,
                        suffix: _S.areaUnit(l),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: const [_DecimalInputFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _S.areaHint(l),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 12.5,
                          height: 1.3,
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: ListingCtaButton(
                    label: _saving ? _S.saving(l) : _S.continueLabel(l),
                    enabled: !_saving,
                    onTap: _continue,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextButton(
                    onPressed: _saving ? null : _continue,
                    child: Text(
                      _S.skip(l),
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 13.5,
                        color: subColor,
                      ),
                    ),
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

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.isDark,
    required this.locale,
    required this.suffix,
    required this.inputFormatters,
    required this.onChanged,
    this.autofocus = false,
    this.keyboardType = TextInputType.number,
  });

  final TextEditingController controller;
  final bool isDark;
  final Locale locale;
  final String suffix;
  final List<TextInputFormatter> inputFormatters;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.32)
        : AppColors.textBlack.withValues(alpha: 0.30);
    final suffixColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              autofocus: autofocus,
              onChanged: onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              inputFormatters: inputFormatters,
              cursorColor: AppColors.splashGreen,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w800,
                fontSize: 26,
                color: textColor,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                hintText: '0',
                hintStyle: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  color: hintColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            suffix,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: suffixColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimateHint extends StatelessWidget {
  const _EstimateHint({
    required this.value,
    required this.isDark,
    required this.locale,
  });

  final double value;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final color = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    return Row(
      children: [
        const Icon(Icons.auto_awesome, size: 16, color: AppColors.splashGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${_S.aiHint(locale)} '),
                TextSpan(
                  text: '${fmtUzsPublic(locale, value.round())} ${_S.soum(locale)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12.5,
              height: 1.3,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Digits-only with thousands grouping (`12 500 000`), cursor kept at the end.
class _MoneyInputFormatter extends TextInputFormatter {
  const _MoneyInputFormatter();

  static const int _maxDigits = 15;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > _maxDigits) digits = digits.substring(0, _maxDigits);
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Maydon (m²) uchun: faqat raqamlar va bitta kasr nuqtasi (`,` → `.`).
class _DecimalInputFormatter extends TextInputFormatter {
  const _DecimalInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var t = newValue.text.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    final firstDot = t.indexOf('.');
    if (firstDot != -1) {
      t = t.substring(0, firstDot + 1) +
          t.substring(firstDot + 1).replaceAll('.', '');
    }
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

class _S {
  const _S._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  static String appBar(Locale l) =>
      _pick(l, 'AI Baholash', 'AI оценка', 'AI valuation');

  static String appBarSub(Locale l) =>
      _pick(l, 'Sotuv narxingiz', 'Ваша цена продажи', 'Your selling price');

  static String heading(Locale l) => _pick(
        l,
        'Qaysi narxda sotmoqchisiz?',
        'По какой цене хотите продать?',
        'What price do you want to sell at?',
      );

  static String subheading(Locale l) => _pick(
        l,
        'Ixtiyoriy. Mutaxassis siz so\'ragan narxni inobatga oladi.',
        'Необязательно. Специалист учтёт запрошенную вами цену.',
        'Optional. The specialist will take your asking price into account.',
      );

  static String soum(Locale l) => _pick(l, 'so\'m', 'сум', 'soum');

  static String areaLabel(Locale l) => _pick(
        l,
        'Bino / uy maydoni',
        'Площадь здания / дома',
        'Building / house area',
      );

  static String areaUnit(Locale l) => _pick(l, 'm²', 'м²', 'm²');

  static String areaHint(Locale l) => _pick(
        l,
        'Ixtiyoriy. Umumiy maydonni m² da kiriting.',
        'Необязательно. Укажите общую площадь в м².',
        'Optional. Enter the total area in m².',
      );

  static String aiHint(Locale l) => _pick(
        l,
        'AI taxminiy bahosi:',
        'Примерная оценка AI:',
        'AI estimate:',
      );

  static String continueLabel(Locale l) =>
      _pick(l, 'Davom etish', 'Продолжить', 'Continue');

  static String skip(Locale l) => _pick(
        l,
        'O\'tkazib yuborish',
        'Пропустить',
        'Skip',
      );

  static String saving(Locale l) =>
      _pick(l, 'Saqlanmoqda...', 'Сохранение...', 'Saving...');

  static String saveFailed(Locale l) => _pick(
        l,
        'Narxni saqlab bo\'lmadi, lekin davom etishingiz mumkin',
        'Не удалось сохранить цену, но вы можете продолжить',
        'Couldn\'t save the price, but you can continue',
      );
}
