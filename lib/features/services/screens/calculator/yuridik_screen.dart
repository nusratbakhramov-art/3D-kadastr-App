import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../auth/auth_storage.dart';
import '../../../auth/widgets/login_required_sheet.dart';
import '../../../market/widgets/listing_cta_button.dart';
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
  /// Tap a service → push its application screen (a full page, like the other
  /// calculator services), not a modal.
  void _openApply(_YuridikItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _YuridikApplyScreen(item: item)),
    );
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
                                  onTap: () => _openApply(services[i]),
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

/// Full-page application screen for one legal service — matches the other
/// calculator services (a pushed page, not a modal). Shows the service, an
/// optional case note, and submits a calculator order (→ user's Arizalar +
/// admin calculator-orders).
class _YuridikApplyScreen extends StatefulWidget {
  const _YuridikApplyScreen({required this.item});

  final _YuridikItem item;

  @override
  State<_YuridikApplyScreen> createState() => _YuridikApplyScreenState();
}

class _YuridikApplyScreenState extends State<_YuridikApplyScreen> {
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
    setState(() => _submitting = true);
    final item = widget.item;
    final total = int.tryParse(item.price.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final trimmed = _note.text.trim();
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
    final item = widget.item;

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
                        title: item.title,
                        subtitle: _pick(locale, 'Ariza topshirish',
                            'Оставить заявку', 'Apply'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          Text(
                            item.description,
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
                                    _pick(locale, 'Narxi', 'Цена', 'Price'),
                                    style: TextStyle(
                                      fontFamily: 'MTSText',
                                      fontSize: 13.5,
                                      color: subColor,
                                    ),
                                  ),
                                ),
                                Text(
                                  item.price,
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
                            _pick(locale, "Qo'shimcha izoh",
                                'Дополнительный комментарий', 'Additional note'),
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
                              hintText: _pick(
                                locale,
                                "Holatingizni qisqacha yozing (ixtiyoriy)",
                                'Кратко опишите ситуацию (необязательно)',
                                'Briefly describe your case (optional)',
                              ),
                              hintStyle:
                                  TextStyle(color: subColor, fontSize: 13.5),
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
                          const SizedBox(height: 12),
                          Text(
                            _pick(
                              locale,
                              "Mutaxassislarimiz siz bilan bog'lanib, narx va shartlarni tasdiqlaydi.",
                              'Наши специалисты свяжутся с вами и подтвердят цену и условия.',
                              'Our specialists will contact you to confirm price and terms.',
                            ),
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: ListingCtaButton(
                        label: _submitting
                            ? _pick(locale, 'Yuborilmoqda...', 'Отправка...',
                                'Submitting...')
                            : _pick(locale, 'Ariza topshirish',
                                'Оставить заявку', 'Submit application'),
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
