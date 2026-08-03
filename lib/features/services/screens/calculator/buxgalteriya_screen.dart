/// Qurilish buxgalteriyasi — quote-only calculator service.
///
/// There is no per-m² tariff for accounting work, so this mirrors the Yuridik
/// flow rather than the m²-based forms: the user describes what they need and
/// submits a calculator order (`category: buxgalteriya`, total 0, "kelishuv
/// asosida"), which lands in their Arizalar and the admin's per-service page.
library;

import 'package:flutter/material.dart';

import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../auth/widgets/login_required_sheet.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../api_calculator_order_service.dart';
import '../../models/calculator_draft.dart';
import '../../models/kadastr_estimate.dart' show kadastrQuoteLabel;
import '../../widgets/service_app_bar.dart';
import 'arxitektura_tz_success_screen.dart';

class BuxgalteriyaScreen extends StatefulWidget {
  const BuxgalteriyaScreen({super.key});

  @override
  State<BuxgalteriyaScreen> createState() => _BuxgalteriyaScreenState();
}

class _BuxgalteriyaScreenState extends State<BuxgalteriyaScreen> {
  final CalculatorOrderApiService _orders = CalculatorOrderApiService();
  final TextEditingController _note = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _orders.dispose();
    _note.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!await ensureLoggedIn(context)) return;
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) return;
    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    setState(() => _submitting = true);
    final trimmed = _note.text.trim();
    final result = CalculatorResult(
      categoryTitle: CalculatorCategory.buxgalteriya.title(locale),
      category: CalculatorCategory.buxgalteriya.name,
      // Quote-only — the operator sets the price after contact.
      totalUzs: 0,
      note: trimmed.isEmpty ? kadastrQuoteLabel(locale) : trimmed,
      lines: const [],
    );
    try {
      final id = await _orders.submit(result: result, token: token);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ArxitekturaTzSuccessScreen(orderId: id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final priceColor = isDark ? const Color(0xFF7DD992) : AppColors.splashGreen;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final locale = Localizations.localeOf(context);

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
                        title: CalculatorCategory.buxgalteriya.title(locale),
                        subtitle:
                            tr(locale, 'services.calc.buxgalteriya.subtitle'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          Text(
                            tr(locale, 'services.calc.buxgalteriya.note'),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 14,
                              height: 1.45,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tr(locale, 'services.calc.yuridik.price'),
                                    style: TextStyle(
                                      fontFamily: 'MTSText',
                                      fontSize: 13.5,
                                      color: subColor,
                                    ),
                                  ),
                                ),
                                Text(
                                  kadastrQuoteLabel(locale),
                                  style: TextStyle(
                                    fontFamily: 'MTSCompact',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: priceColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            tr(locale, 'services.calc.buxgalteriya.ask'),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _note,
                            minLines: 3,
                            maxLines: 6,
                            style: TextStyle(color: titleColor, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: tr(
                                locale,
                                'services.calc.buxgalteriya.note_hint',
                              ),
                              hintStyle:
                                  TextStyle(color: subColor, fontSize: 13.5),
                              filled: true,
                              fillColor:
                                  isDark ? const Color(0xFF1F2426) : Colors.white,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF2C3133)
                                      : const Color(0xFFE3E5E8),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppColors.splashGreen,
                                  width: 1.4,
                                ),
                              ),
                              contentPadding: const EdgeInsets.all(14),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr(locale, 'services.calc.yuridik.contact_note'),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 12.5,
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
                        label: _submitting
                            ? tr(locale, 'services.calc.buxgalteriya.sending')
                            : tr(locale, 'services.calc.yuridik.submit'),
                        enabled: !_submitting,
                        onTap: _submit,
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
