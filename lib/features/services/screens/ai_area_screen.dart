/// AI Baholash — birinchi qadam skandan keyin: obyekt maydonini (m²) so'raydi.
///
/// Alohida ekran (davreestr lookup'idan oldin), chunki davreestr endi ixtiyoriy
/// (skip qilinishi mumkin) — shu bois obyekt maydonini foydalanuvchidan shu
/// yerda aniq olamiz. Kiritilgan qiymat bundle'ga (`areaM2`) yoziladi va submit
/// payloadida `total_area` sifatida ketadi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../ai_draft_saver.dart';
import '../api_cadastre_service.dart';
import '../models/ai_scan_result.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_cadastre_screen.dart';

class AiAreaScreen extends StatefulWidget {
  const AiAreaScreen({
    super.key,
    this.scan,
    this.draftId,
    this.scanJobId,
    this.initialArea,
    this.initialCadastre,
  });

  /// 3D skan natijasi (oldingi qadamdan) — keyingi ekranlarga uzatiladi.
  final AiScanResult? scan;

  /// Skandan keyin yaratilgan DRAFT ariza id.
  final int? draftId;

  /// Resume oqimi: skanlangan 3D model bor draft id (cadastre ekraniga uzatiladi).
  final int? scanJobId;

  /// Resume oqimi: draft'dan tiklangan obyekt maydoni (m²) — maydon oldindan
  /// to'ldiriladi.
  final double? initialArea;

  /// Oldin aniqlangan davreestr natijasi (resume yoki Orqaga qaytish). Keyingi
  /// kadastr qadamiga uzatiladi, shunda Orqaga→Oldinga bosганда yo'qolmaydi.
  final CadastreLookupResult? initialCadastre;

  @override
  State<AiAreaScreen> createState() => _AiAreaScreenState();
}

class _AiAreaScreenState extends State<AiAreaScreen> {
  final TextEditingController _areaCtrl = TextEditingController();

  /// The cadastre resolved on the next step. Held here so re-entering the
  /// cadastre screen (Back → Davom etish) restores it instead of starting blank.
  CadastreLookupResult? _cadastre;

  @override
  void initState() {
    super.initState();
    _cadastre = widget.initialCadastre;
    final a = widget.initialArea;
    if (a != null && a > 0) {
      _areaCtrl.text =
          a == a.roundToDouble() ? a.toInt().toString() : a.toString();
    }
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    super.dispose();
  }

  double? get _area {
    final t = _areaCtrl.text.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _continue() async {
    final area = _area;
    if (area == null || area <= 0) return;
    HapticFeedback.lightImpact();
    // Make sure a DRAFT exists so every following step autosaves. Normally the
    // draft is created after the 3D scan; this covers the paths where it wasn't
    // (the testing skip, or a scan whose draft-create failed). No-op when one
    // already exists. Seeds `total_area` so the area isn't lost on resume.
    var draftId = widget.draftId;
    draftId ??= await createAiDraft(
      payload: {'total_area': area},
      currentStep: 'cadastre',
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/area'),
        builder: (_) => AiCadastreScreen(
          scan: widget.scan,
          draftId: draftId,
          scanJobId: widget.scanJobId,
          areaM2: area,
          initial: _cadastre,
          onResolved: (r) => _cadastre = r,
        ),
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
                  child: StepProgressBar(count: 8, activeIndex: 0),
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
                      _AreaField(
                        controller: _areaCtrl,
                        isDark: isDark,
                        suffix: _S.areaUnit(l),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _S.continueLabel(l),
                    enabled: (_area ?? 0) > 0,
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

class _AreaField extends StatelessWidget {
  const _AreaField({
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              onChanged: onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              inputFormatters: const [_DecimalInputFormatter()],
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

/// Faqat raqamlar va bitta kasr nuqtasi (`,` → `.`).
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
      _pick(l, 'Obyekt maydoni', 'Площадь объекта', 'Object area');

  static String heading(Locale l) => _pick(
        l,
        'Obyekt maydoni qancha?',
        'Какая площадь объекта?',
        "What is the object's area?",
      );

  static String subheading(Locale l) => _pick(
        l,
        'Bino / uy umumiy maydonini m² da kiriting.',
        'Укажите общую площадь здания / дома в м².',
        'Enter the total building / house area in m².',
      );

  static String areaUnit(Locale l) => _pick(l, 'm²', 'м²', 'm²');

  static String areaHint(Locale l) => _pick(
        l,
        'Bu maydon baholashda ishlatiladi.',
        'Эта площадь используется в оценке.',
        'This area is used in the valuation.',
      );

  static String continueLabel(Locale l) =>
      _pick(l, 'Davom etish', 'Продолжить', 'Continue');
}
