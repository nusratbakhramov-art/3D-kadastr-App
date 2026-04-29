import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../widgets/service_app_bar.dart';

class YuridikScreen extends StatelessWidget {
  const YuridikScreen({super.key});

  static const _services = <_YuridikItem>[
    _YuridikItem(
      title: 'Yuridik maslahat',
      description: "Bir savol yoki holat bo'yicha bir martalik maslahat",
      price: "500 000 so'm",
    ),
    _YuridikItem(
      title: 'Hujjat tayyorlash',
      description: "Shartnoma, ariza, da'vo, javob va boshqa hujjatlar",
      price: "1 500 000 so'm",
    ),
    _YuridikItem(
      title: 'Sudda himoya (yuridik vakillik)',
      description: "Fuqarolik, iqtisodiy, jinoyat ishlari bo'yicha",
      price: "5 000 000 – 20 000 000 so'm",
    ),
    _YuridikItem(
      title: "Davlat ro'yxatidan o'tkazish",
      description: "Shartnomani ro'yxatga olish va boshqa rasmiyatlar",
      price: "2 000 000 – 20 000 000 so'm",
    ),
    _YuridikItem(
      title: 'Korxona ulushini hisoblash',
      description: 'Aksiya, ish va mahsulot ulushini hisoblash',
      price: "3 000 000 so'm",
    ),
    _YuridikItem(
      title: 'Sud orqali undirib olish',
      description: 'Tovon va qarzni undirish ishlari',
      price: '5–20% komissiya',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
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
                        title: 'Yuridik xizmat',
                        subtitle: 'Xizmatlar va narxlari',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          Text(
                            'Quyidagi xizmatlar uchun aniq narx murojaat asosida belgilanadi.',
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 13,
                              height: 1.4,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (var i = 0; i < _services.length; i++) ...[
                            _ServiceCard(
                              item: _services[i],
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
