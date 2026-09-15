/// Lenta va "Mening e'lonlarim" ro'yxatidagi karta.
///
/// `market/widgets/listing_card.dart` QAYTA ISHLATILMADI: u `MarketListing`
/// (3D model katalogi) turiga qattiq bog'langan va e'lonning `status`,
/// `rejectionReason` kabi maydonlarini bilmaydi. Uni umumiylashtirish ikkita
/// mustaqil domenni bir widget ichida ushlab turishga olib kelardi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/color_tokens.dart';
import '../models/bozor_listing.dart';

class BozorListingCard extends StatelessWidget {
  const BozorListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.showStatus = false,
  });

  final BozorListing listing;
  final VoidCallback onTap;

  /// Moderatsiya holatini ko'rsatish. Ommaviy lentada KERAK EMAS — u yerda
  /// hammasi `approved`, ya'ni har kartada bir xil yashil nishon turishi
  /// faqat shovqin bo'lardi. "Mening e'lonlarim" da esa bu asosiy ma'lumot.
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF121617) : Colors.white;
    final title = isDark ? Colors.white : AppColors.textBlack;
    final meta = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF767A80);
    final cover = listing.coverImageUrl;
    final rooms = listing.roomsAreaLine(l);

    return Material(
      color: card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: isDark
                ? null
                : const Border.fromBorderSide(
                    BorderSide(color: Color(0xFFE3E5E8)),
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: cover == null
                    ? _NoPhoto(isDark: isDark)
                    : Image.network(
                        cover,
                        fit: BoxFit.cover,
                        // Rasm yuklanmasa (S3 sozlanmagan, tarmoq yo'q,
                        // fayl o'chirilgan) karta BUZILMASIN.
                        errorBuilder: (_, _, _) => _NoPhoto(isDark: isDark),
                        loadingBuilder: (_, child, progress) =>
                            progress == null ? child : _NoPhoto(isDark: isDark),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showStatus) ...[
                      _StatusChip(status: listing.status),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      listing.formattedPrice(l),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: title,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 14,
                        height: 1.3,
                        color: title,
                      ),
                    ),
                    if (rooms != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        rooms,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 13,
                          color: meta,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      listing.regionLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 13,
                        color: meta,
                      ),
                    ),
                    // Rad etilgan e'londa SABAB kartada ko'rinadi: egasi
                    // detalga kirmasdan nima tuzatishni bilishi kerak.
                    // Backend kafolatlaydi: `rejected` da sabab bo'sh emas.
                    if (showStatus &&
                        listing.status == ListingStatus.rejected &&
                        (listing.rejectionReason ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        listing.rejectionReason!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 12,
                          height: 1.35,
                          color: Color(0xFFE0492A),
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

class _NoPhoto extends StatelessWidget {
  const _NoPhoto({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: isDark ? const Color(0xFF1F2426) : const Color(0xFFF1F3F5),
    child: Center(
      child: Icon(
        Icons.image_outlined,
        size: 28,
        color: isDark ? Colors.white24 : const Color(0xFFB9BEC4),
      ),
    ),
  );
}

/// Moderatsiya holati. Ranglar ma'no bilan: kutish — neytral, tasdiqlangan —
/// yashil, rad etilgan — qizil, arxiv — kul rang (yashil "hammasi joyida"
/// degan noto'g'ri xabar bermasin).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final (String key, Color color) = switch (status) {
      ListingStatus.pending => ('listings.status.moderation', const Color(0xFFE8A33D)),
      ListingStatus.approved => ('listings.status.approved', AppColors.splashGreen),
      ListingStatus.rejected => ('listings.status.rejected', const Color(0xFFE0492A)),
      ListingStatus.archived => ('listings.status.archived', ColorTokens.secondaryText(context)),
      // Server yangi holat qo'shsa nishon bo'sh qolmasin.
      ListingStatus.unknown => ('listings.status.moderation', ColorTokens.secondaryText(context)),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          tr(l, key),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: color,
          ),
        ),
      ),
    );
  }
}
