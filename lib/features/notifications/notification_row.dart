// Bildirishnomalar ro'yxatining bitta satri va kun sarlavhasi.
//
// Avval har bir element alohida KARTA edi: yuqorida kulrang sana chipi, ostida
// sarlavha va matn, atrofida ramka. Uchta muammo bor edi:
//
//   * Sana eng baland ovozli element edi — u metama'lumot bo'lsa ham
//     sarlavhadan YUQORIDA va ramkali chip ichida turardi.
//   * Barcha satrlar bir xil ko'rinardi. `iconForType` modelda bor edi,
//     lekin ro'yxat undan foydalanmasdi — to'lov, skan va yangilanish
//     farqsiz edi.
//   * O'qilmagan holat butun kartani yashil ramkaga olardi. Ketma-ket to'rtta
//     o'qilmagan xabar — butun ekran yashil quti, urg'u ma'nosini yo'qotadi.
//
// Endi bu lenta: chapda turni bildiruvchi belgi, o'ngda vaqt, o'qilmaganini
// bitta kichik nuqta aytadi. Sana kunlik sarlavhaga chiqdi.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import 'notification_date.dart';
import 'notification_model.dart';

/// Kun ajratgichi — "BUGUN", "KECHA", "12.06.2026".
class NotificationDayHeader extends StatelessWidget {
  const NotificationDayHeader({
    super.key,
    required this.at,
    required this.locale,
    required this.first,
  });

  final DateTime at;
  final Locale locale;

  /// Birinchi guruh tepada kamroq joy oladi — ekran sarlavhasi allaqachon bor.
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 4 : 26, 4, 10),
      child: Text(
        notificationDayLabel(at, locale).toUpperCase(),
        style: TextStyle(
          fontFamily: 'MTSCompact',
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: ColorTokens.tertiaryText(context),
        ),
      ),
    );
  }
}

class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.item,
    required this.onTap,
  });

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (icon, tint) = iconForType(item.type);
    // Neon brend yashili qorong'ida porlaydi, oq fonda esa deyarli ko'rinmaydi.
    final accent = (tint == AppColors.splashGreen && !isDark)
        ? AppColors.brandGreen
        : tint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hapticTap(onTap),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Badge(item: item, icon: icon, accent: accent),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              // O'qilgan xabar ham o'qilishi kerak — u faqat
                              // TINCHROQ, o'chirilgan emas.
                              fontWeight: item.unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 15.5,
                              height: 1.25,
                              color: item.unread
                                  ? ColorTokens.primaryText(context)
                                  : ColorTokens.secondaryText(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            notificationTime(item.at),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: ColorTokens.tertiaryText(context),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (item.unread) ...[
                          const SizedBox(width: 7),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.splashGreen
                                    : AppColors.brandGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item.message.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 14,
                          height: 1.35,
                          color: ColorTokens.tertiaryText(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chapdagi belgi — "bu nima haqida" degan yagona slot.
///
/// Adminka rasm yuborgan bo'lsa, rasmning O'ZI shu slotga tushadi: ro'yxatda
/// 160px balandlikdagi banner satrlar ritmini buzardi va har bir elementni
/// ekranning uchdan biriga aylantirardi.
class _Badge extends StatelessWidget {
  const _Badge({required this.item, required this.icon, required this.accent});

  final AppNotification item;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const size = 42.0;
    final radius = BorderRadius.circular(13);

    if (item.imageUrl != null) {
      return ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          imageUrl: item.imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            width: size,
            height: size,
            color: ColorTokens.iconBg(context),
          ),
          errorWidget: (_, _, _) => _Glyph(icon: icon, accent: accent),
        ),
      );
    }
    return _Glyph(icon: icon, accent: accent);
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, size: 20, color: accent),
    );
  }
}
