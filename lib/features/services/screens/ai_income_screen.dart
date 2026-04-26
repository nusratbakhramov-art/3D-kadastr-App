import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/ai_valuation_draft.dart';
import '../widgets/choice_tile.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_result_screen.dart';

class AiIncomeScreen extends StatefulWidget {
  const AiIncomeScreen({super.key, required this.draft});

  final AiValuationDraft draft;

  @override
  State<AiIncomeScreen> createState() => _AiIncomeScreenState();
}

class _AiIncomeScreenState extends State<AiIncomeScreen> {
  AiUsageType? _usage;
  final TextEditingController _incomeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _usage = widget.draft.usageType;
    if (widget.draft.monthlyIncomeUzs != null) {
      _incomeController.text = widget.draft.monthlyIncomeUzs!.toString();
    }
  }

  @override
  void dispose() {
    _incomeController.dispose();
    super.dispose();
  }

  void _continue() {
    final income = int.tryParse(
      _incomeController.text.replaceAll(RegExp(r'\D'), ''),
    );
    final draft = widget.draft.copyWith(
      usageType: _usage,
      monthlyIncomeUzs: income,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AiResultScreen(draft: draft)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final labelColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

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
                      child: const ServiceAppBar(
                        title: 'AI Baholash',
                        subtitle: 'Daromadlilik (ixtiyoriy)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 4, activeIndex: 2),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          Text(
                            'Foydalanish turi',
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.25,
                              color: labelColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Daromad ma\'lumotini qo\'shsangiz, baholash aniqligi oshadi.',
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              height: 1.3,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (final u in AiUsageType.values) ...[
                            ChoiceTile(
                              label: u.label,
                              selected: _usage == u,
                              onTap: () => setState(() => _usage = u),
                            ),
                            const SizedBox(height: 8),
                          ],
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SizeTransition(
                                    sizeFactor: animation,
                                    axisAlignment: -1,
                                    child: child,
                                  ),
                                ),
                            child: _usage == AiUsageType.rental
                                ? Padding(
                                    key: const ValueKey('income'),
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Oylik ijara (so\'m)',
                                          style: TextStyle(
                                            fontFamily: 'MTSCompact',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            height: 1.25,
                                            color: labelColor,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        _IncomeInput(
                                          controller: _incomeController,
                                          isDark: isDark,
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey('empty')),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: 'Baholash',
                        enabled: true,
                        onTap: _continue,
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

class _IncomeInput extends StatelessWidget {
  const _IncomeInput({required this.controller, required this.isDark});

  final TextEditingController controller;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFB4B9BF);

    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [_ThousandsFormatter()],
      style: TextStyle(fontFamily: 'MTSText', fontSize: 15, color: textColor),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        hintText: 'Masalan: 4 500 000',
        hintStyle: TextStyle(
          fontFamily: 'MTSText',
          fontSize: 15,
          color: hintColor,
        ),
        filled: true,
        fillColor: fill,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.splashGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final buf = StringBuffer();
    final reversed = digits.split('').reversed.toList();
    for (var i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(' ');
      buf.write(reversed[i]);
    }
    final formatted = buf.toString().split('').reversed.join();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
