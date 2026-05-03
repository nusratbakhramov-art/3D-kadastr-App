import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../widgets/service_app_bar.dart';

class YuridikScreen extends StatelessWidget {
  const YuridikScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final locale = Localizations.localeOf(context);
    final services = _YuridikItem.all(locale);

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
                      child: ListView(
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
                            ),
                            const SizedBox(height: 10),
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

class _YuridikItem {
  const _YuridikItem({
    required this.title,
    required this.description,
    required this.price,
  });
  final String title;
  final String description;
  final String price;

  static List<_YuridikItem> all(Locale l) => [
        _YuridikItem(
          title: _pick(l, 'Yuridik maslahat', 'Юридическая консультация',
              'Legal consultation'),
          description: _pick(
            l,
            "Bir savol yoki holat bo'yicha bir martalik maslahat",
            'Разовая консультация по вопросу или ситуации',
            'One-time consultation on a question or matter',
          ),
          price: _pick(l, "500 000 so'm", '500 000 сум', '500,000 UZS'),
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
          price: _pick(l, "1 500 000 so'm", '1 500 000 сум', '1,500,000 UZS'),
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
          price: _pick(
            l,
            "5 000 000 – 20 000 000 so'm",
            '5 000 000 – 20 000 000 сум',
            '5,000,000 – 20,000,000 UZS',
          ),
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
          price: _pick(
            l,
            "2 000 000 – 20 000 000 so'm/oy",
            '2 000 000 – 20 000 000 сум/мес',
            '2,000,000 – 20,000,000 UZS/month',
          ),
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
          price: _pick(l, "3 000 000 so'm", '3 000 000 сум', '3,000,000 UZS'),
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
          price: _pick(l, '5–20% komissiya', '5–20% комиссия', '5–20% commission'),
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
  });

  final _YuridikItem item;
  final Color titleColor;
  final Color subColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final priceColor = isDark
        ? const Color(0xFF7DD992)
        : AppColors.splashGreen;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    );
  }
}
