import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../auth/widgets/login_required_sheet.dart';
import '../../api_calculator_order_service.dart';
import '../../data/calculator_pricing_store.dart';
import '../../models/calculator_draft.dart';
import '../../models/calculator_pricing.dart';
import '../../widgets/service_app_bar.dart';
import 'arxitektura_tz_success_screen.dart';

class YuridikScreen extends StatefulWidget {
  const YuridikScreen({super.key});

  @override
  State<YuridikScreen> createState() => _YuridikScreenState();
}

class _YuridikScreenState extends State<YuridikScreen> {
  final CalculatorOrderApiService _orders = CalculatorOrderApiService();

  @override
  void dispose() {
    _orders.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Tap a service → open a detail drawer (its info + an optional note + submit).
  /// Login is checked before opening so the login prompt isn't nested inside the
  /// sheet. On success the sheet returns the order id and we show the success
  /// screen.
  Future<void> _openSheet(_YuridikItem item) async {
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _YuridikSheet(
        item: item,
        onSubmit: (note) => _submitOrder(item, note),
      ),
    );
    if (id != null && mounted) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ArxitekturaTzSuccessScreen(orderId: id),
        ),
      );
    }
  }

  /// Submit one legal-service application. Reuses the calculator-order endpoint,
  /// so it lands in the user's "Arizalar" and the admin's calculator-orders view
  /// — no separate pipeline. Returns the new order id, or null on failure.
  Future<int?> _submitOrder(_YuridikItem item, String note) async {
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) return null;
    final total = int.tryParse(item.price.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final trimmed = note.trim();
    final fullNote = trimmed.isEmpty
        ? '${item.title} — ${item.description}'
        : '${item.title} — ${item.description}\n\nIzoh: $trimmed';
    final result = CalculatorResult(
      categoryTitle: 'Yuridik xizmat',
      totalUzs: total,
      note: fullNote,
      lines: [CalculatorLine(item.title, item.price)],
    );
    try {
      return await _orders.submit(result: result, token: token);
    } catch (e) {
      _snack('$e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
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
                        title: _Strings.title(locale),
                        subtitle: _Strings.subtitle(locale),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ValueListenableBuilder<CalculatorPricing>(
                        valueListenable: calculatorPricingNotifier,
                        builder: (context, pricing, _) {
                          final services = _YuridikItem.all(locale, pricing);
                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            children: [
                              Text(
                                _Strings.note(locale),
                                style: TextStyle(
                                  fontFamily: 'MTSText',
                                  fontSize: 13,
                                  height: 1.4,
                                  color: subColor,
                                ),
                              ),
                              const SizedBox(height: 14),
                              for (var i = 0; i < services.length; i++) ...[
                                _ServiceCard(
                                  item: services[i],
                                  titleColor: headingColor,
                                  subColor: subColor,
                                  onTap: () => _openSheet(services[i]),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          );
                        },
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

class _YuridikItem {
  const _YuridikItem({
    required this.title,
    required this.description,
    required this.price,
  });
  final String title;
  final String description;
  final String price;

  static List<_YuridikItem> all(Locale l, CalculatorPricing pricing) => [
        _YuridikItem(
          title: _pick(l, 'Yuridik maslahat', 'Юридическая консультация',
              'Legal consultation'),
          description: _pick(
            l,
            "Bir savol yoki holat bo'yicha bir martalik maslahat",
            'Разовая консультация по вопросу или ситуации',
            'One-time consultation on a question or matter',
          ),
          price: pricing.yuridikValue('yuridik.maslahat', l),
        ),
        _YuridikItem(
          title: _pick(
              l, 'Hujjat tayyorlash', 'Подготовка документов', 'Document preparation'),
          description: _pick(
            l,
            "Shartnoma, ariza, da'vo, javob va boshqa hujjatlar",
            'Договор, заявление, иск, ответ и другие документы',
            'Contract, application, claim, response and other documents',
          ),
          price: pricing.yuridikValue('yuridik.hujjat', l),
        ),
        _YuridikItem(
          title: _pick(
            l,
            'Sudda himoya (yuridik vakillik)',
            'Защита в суде (юридическое представительство)',
            'Court representation',
          ),
          description: _pick(
            l,
            "Fuqarolik, iqtisodiy, jinoyat ishlari bo'yicha",
            'По гражданским, экономическим, уголовным делам',
            'For civil, economic, criminal cases',
          ),
          price: pricing.yuridikValue('yuridik.sud', l),
        ),
        _YuridikItem(
          title: _pick(
            l,
            'Korxonalar uchun autsorsing',
            'Аутсорсинг для предприятий',
            'Outsourcing for businesses',
          ),
          description: _pick(
            l,
            'Doimiy yuridik kuzatuv (oy uchun)',
            'Постоянное юридическое сопровождение (за месяц)',
            'Continuous legal support (per month)',
          ),
          price: pricing.yuridikValue('yuridik.autsorsing', l),
        ),
        _YuridikItem(
          title: _pick(
              l, "Ro'yxatdan o'tkazish", 'Регистрация', 'Registration'),
          description: _pick(
            l,
            "MChJ ochish, lisenziya olish va boshqalar",
            'Открытие ООО, получение лицензии и др.',
            'LLC formation, licensing and more',
          ),
          price: pricing.yuridikValue('yuridik.royxat', l),
        ),
        _YuridikItem(
          title: _pick(
            l,
            'Qarz undirish va ijro ishlari',
            'Взыскание долгов',
            'Debt collection',
          ),
          description: _pick(
            l,
            'Debitor qarzlarni qaytarish — ish hajmidan',
            'Возврат дебиторской задолженности — от объёма работ',
            'Recovery of receivables — based on workload',
          ),
          price: pricing.yuridikValue('yuridik.qarz', l),
        ),
      ];
}

String _pick(Locale l, String uz, String ru, String en) =>
    switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

class _Strings {
  const _Strings._();

  static String title(Locale l) =>
      _pick(l, 'Yuridik xizmat', 'Юридические услуги', 'Legal services');

  static String subtitle(Locale l) =>
      _pick(l, 'Xizmatlar va narxlari', 'Услуги и цены', 'Services & prices');

  static String note(Locale l) => _pick(
        l,
        "Quyidagi xizmatlar uchun aniq narx murojaat asosida belgilanadi.",
        'Точная цена для следующих услуг определяется при обращении.',
        'Exact price for the following services is determined on request.',
      );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.item,
    required this.titleColor,
    required this.subColor,
    required this.onTap,
  });

  final _YuridikItem item;
  final Color titleColor;
  final Color subColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final priceColor = isDark
        ? const Color(0xFF7DD992)
        : AppColors.splashGreen;

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12.5,
                        height: 1.4,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.price,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: priceColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: subColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet drawer for one legal service: shows its details, an optional
/// note, and the "Ariza topshirish" action. `onSubmit` returns the new order id
/// (or null on failure); on success the sheet pops with that id.
class _YuridikSheet extends StatefulWidget {
  const _YuridikSheet({required this.item, required this.onSubmit});

  final _YuridikItem item;
  final Future<int?> Function(String note) onSubmit;

  @override
  State<_YuridikSheet> createState() => _YuridikSheetState();
}

class _YuridikSheetState extends State<_YuridikSheet> {
  final TextEditingController _note = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final id = await widget.onSubmit(_note.text);
    if (!mounted) return;
    if (id != null) {
      Navigator.of(context).pop(id);
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF15191A) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final priceColor = isDark ? const Color(0xFF7DD992) : AppColors.splashGreen;
    final locale = Localizations.localeOf(context);
    final item = widget.item;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: subColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                item.title,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  height: 1.2,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.description,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 13.5,
                  height: 1.4,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.price,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: priceColor,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                style: TextStyle(color: titleColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _pick(
                    locale,
                    "Holatingizni qisqacha yozing (ixtiyoriy)",
                    'Кратко опишите ситуацию (необязательно)',
                    'Briefly describe your case (optional)',
                  ),
                  hintStyle: TextStyle(color: subColor, fontSize: 13.5),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1F2426)
                      : const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: AppColors.splashGreen,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _submitting ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Center(
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Text(
                                _pick(locale, 'Ariza topshirish',
                                    'Оставить заявку', 'Submit application'),
                                style: const TextStyle(
                                  fontFamily: 'MTSCompact',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
