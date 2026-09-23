import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/remote_image.dart';
import '../models/market_listing.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final MarketListing listing;
  final ValueChanged<MarketListing> onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF121617) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final metaColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF767A80);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: isDark
          ? BorderSide.none
          : const BorderSide(color: Color(0xFFE3E5E8)),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 6),
            child: child,
          ),
        );
      },
      child: Material(
        color: cardColor,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap(listing);
          },
          child: Column(
            // Masonry grid bolalarni cheksiz balandlikda o'lchaydi — Column
            // kontent bo'yicha o'lchanishi shart (max bo'lsa RenderFlex uziladi).
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                clipBehavior: Clip.hardEdge,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'listing.${listing.id}',
                        child: _ListingImage(url: listing.imageUrl),
                      ),
                      if (listing.priceUzs <= 0)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.splashGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tr(locale, 'market.listing.free'),
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                height: 1.2,
                                color: Color(0xFF011606),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PriceLine(price: listing.priceUzs, color: titleColor),
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.2,
                        color: titleColor,
                      ),
                    ),
                    // Hudud va maydon PROD'da ko'pincha to'ldirilmagan
                    // (2026-09-23: 265 ta modeldan 245 tasida hudud, 213
                    // tasida maydon yo'q). Ilgari qator baribir chizilardi:
                    // xarita ikonkasi yonida BO'SH joy, o'lchagich yonida
                    // esa «0 m²» — ya'ni noto'g'ri fakt. Ulashish matni va
                    // karusel allaqachon shu qoidada.
                    if (listing.district.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _MetaRow(
                        iconAsset: 'assets/icons/map.svg',
                        text: listing.district.trim(),
                        color: metaColor,
                      ),
                    ],
                    if (listing.areaM2 > 0) ...[
                      const SizedBox(height: 2),
                      _MetaRow(
                        iconAsset: 'assets/icons/ruler-triangle.svg',
                        text: '${listing.areaM2} ${tr(locale, 'bozor.unit.m²')}',
                        color: metaColor,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _BatafsilButton(
                      locale: locale,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onTap(listing);
                      },
                    ),
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

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.price, required this.color});

  final int price;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (price <= 0) return const SizedBox.shrink();

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: _format(price),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.25,
              color: color,
            ),
          ),
          TextSpan(
            text: ' UZS',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.25,
              color: color.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  String _format(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final remaining = s.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write(' ');
    }
    return buf.toString();
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.iconAsset,
    required this.text,
    required this.color,
  });

  final String iconAsset;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(iconAsset, width: 16, height: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              height: 1.2,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _BatafsilButton extends StatelessWidget {
  const _BatafsilButton({required this.locale, required this.onTap});

  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.splashGreen,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tr(locale, 'market.card.details'),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.2,
                  color: AppColors.buttonTextBlack,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: AppColors.buttonTextBlack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingImage extends StatelessWidget {
  const _ListingImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return RemoteImage(url: url, memCacheWidth: 480);
  }
}
