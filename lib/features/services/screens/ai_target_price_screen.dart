/// AI Baholash — natijadan OLDINGI qadam: foydalanuvchidan MAQSADLI sotuv
/// narxini so'raydi ("Qaysi narxda sotmoqchisiz?").
///
/// Ixtiyoriy — bo'sh qoldirib davom etish mumkin. Kiritilgan qiymat bundle'ga
/// (`targetSellPrice`) yoziladi; keyingi (natija) ekrani arizani yaratgach uni
/// `PATCH /ai-valuations/{id}/target-price` orqali biriktiradi — shu bois
/// baholovchi qancha so'ralayotganini boshidanoq ko'radi. Keyin natija ekrani.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_status_screen.dart';

class AiTargetPriceScreen extends StatefulWidget {
  const AiTargetPriceScreen({super.key, required this.bundle});

  /// To'liq wizard bundle — narx shunga yoziladi va natija ekraniga uzatiladi.
  final AiBaholashBundle bundle;

  @override
  State<AiTargetPriceScreen> createState() => _AiTargetPriceScreenState();
}

class _AiTargetPriceScreenState extends State<AiTargetPriceScreen> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? get _enteredPrice {
    final digits = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  void _continue() {
    HapticFeedback.lightImpact();
    // Narxni bundle'ga yozamiz (ixtiyoriy) — natija ekrani ariza yaratgach
    // PATCH qiladi. Keyin hisoblash/natija ekraniga o'tamiz.
    widget.bundle.targetSellPrice = _enteredPrice;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/status'),
        builder: (_) => AiStatusScreen(bundle: widget.bundle),
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
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(count: 8, activeIndex: 7),
                ),
                const SizedBox(height: 12),
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
                        suffix: _S.soum(l),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      _AssessmentNote(text: _S.assessment(l), isDark: isDark),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: ListingCtaButton(
                    label: _S.continueLabel(l),
                    onTap: _continue,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextButton(
                    onPressed: _continue,
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
    required this.suffix,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isDark;
  final String suffix;
  final ValueChanged<String> onChanged;

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
              keyboardType: TextInputType.number,
              autofocus: true,
              onChanged: onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              inputFormatters: const [_MoneyInputFormatter()],
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

/// Yashil "check" bilan — foydalanuvchi baholash xulosasini olishini bildiradi.
class _AssessmentNote extends StatelessWidget {
  const _AssessmentNote({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? AppColors.splashGreen.withValues(alpha: 0.12)
        : AppColors.splashGreen.withValues(alpha: 0.08);
    final textColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.splashGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_outlined,
              size: 20, color: AppColors.splashGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
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
        'Siz tomoningizdan taklif etilayotgan narx summasini yozing',
        'Укажите сумму цены, предлагаемую с вашей стороны',
        'Enter the price amount you are proposing',
      );

  static String subheading(Locale l) => _pick(
        l,
        'Ixtiyoriy. Mutaxassis siz taklif etgan narxni inobatga oladi.',
        'Необязательно. Специалист учтёт предложенную вами цену.',
        'Optional. The specialist will take your proposed price into account.',
      );

  static String assessment(Locale l) => _pick(
        l,
        'Ko\'chmas mulk bozor qiymatini baholash xulosasini olasiz',
        'Вы получите заключение об оценке рыночной стоимости недвижимости',
        'You will receive a real-estate market-value assessment report',
      );

  static String soum(Locale l) => _pick(l, 'so\'m', 'сум', 'soum');

  static String continueLabel(Locale l) =>
      _pick(l, 'Davom etish', 'Продолжить', 'Continue');

  static String skip(Locale l) => _pick(
        l,
        'O\'tkazib yuborish',
        'Пропустить',
        'Skip',
      );
}
