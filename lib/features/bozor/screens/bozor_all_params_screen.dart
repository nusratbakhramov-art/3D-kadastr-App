/// "Barcha parametrlar" — 3-qadamning to'liq ro'yxati.
///
/// Dizaynda bu alohida to'liq ekran (varaq emas): tepasida orqaga tugmasi,
/// "Параметры" sarlavhasi va o'ngda "Готово". Ikkita bo'lim — asosiy va
/// qo'shimcha.
///
/// Maydonlar 3/7 ekrani bilan BIR XIL [ParamForm] orqali chiziladi va bir xil
/// `values` xaritasini to'ldiradi, shuning uchun bu yerda kiritilgan qiymat
/// qadamga qaytganda ham turadi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../data/param_options.dart';
import '../models/param_schema.dart';
import '../widgets/param_form.dart';

class BozorAllParamsScreen extends StatefulWidget {
  const BozorAllParamsScreen({
    super.key,
    required this.fields,
    required this.values,
    required this.optionsRepository,
  });

  final List<ParamField> fields;
  final ParamValues values;

  /// Qadam ekranidan keladi — kesh bo'lishilgan bo'lishi uchun.
  final ParamOptionsRepository optionsRepository;

  @override
  State<BozorAllParamsScreen> createState() => _BozorAllParamsScreenState();
}

class _BozorAllParamsScreenState extends State<BozorAllParamsScreen> {
  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final fg = isDark ? Colors.white : AppColors.textBlack;

    final main = widget.fields
        .where((f) => f.section == ParamSection.main)
        .toList();
    final extra = widget.fields
        .where((f) => f.section == ParamSection.extra)
        .toList();

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
                    _Header(
                      title: tr(l, 'bozor.params.title'),
                      doneLabel: tr(l, 'bozor.common.done'),
                      onDone: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          if (main.isNotEmpty) ...[
                            _SectionTitle(
                              text: tr(l, 'bozor.params.section.main'),
                              color: fg,
                            ),
                            const SizedBox(height: 12),
                            ParamForm(
                              fields: main,
                              values: widget.values,
                              onChanged: () => setState(() {}),
                              optionsRepository: widget.optionsRepository,
                            ),
                          ],
                          if (extra.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _SectionTitle(
                              text: tr(l, 'bozor.params.section.extra'),
                              color: fg,
                            ),
                            const SizedBox(height: 12),
                            ParamForm(
                              fields: extra,
                              values: widget.values,
                              onChanged: () => setState(() {}),
                              optionsRepository: widget.optionsRepository,
                            ),
                          ],
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

/// Sehrgar qadamlaridan farqli sarlavha: o'ngda "Tayyor" matn-harakati bor,
/// pastda esa tugma yo'q — bu ekran qadam emas, ro'yxatning davomi.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.doneLabel,
    required this.onDone,
  });

  final String title;
  final String doneLabel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  height: 1.2,
                  color: fg,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: fg),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDone,
                child: Text(
                  doneLabel,
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.splashGreen,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'MTSCompact',
        fontWeight: FontWeight.w700,
        fontSize: 17,
        height: 1.25,
        color: color,
      ),
    );
  }
}
