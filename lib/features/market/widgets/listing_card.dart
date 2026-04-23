import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/app_colors.dart';
import '../models/market_listing.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final MarketListing listing;
  final ValueChanged<MarketListing> onTap;

  @override
  Widget build(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                clipBehavior: Clip.hardEdge,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Hero(
                    tag: 'listing.${listing.id}',
                    child: _ListingImage(url: listing.imageUrl),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PriceLine(price: listing.priceUzs, color: titleColor),
                      Text(
                        listing.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.2,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _MetaRow(
                        iconAsset: 'assets/icons/map.svg',
                        text: listing.district,
                        color: metaColor,
                      ),
                      const SizedBox(height: 2),
                      _MetaRow(
                        iconAsset: 'assets/icons/ruler-triangle.svg',
                        text: '${listing.areaM2} m²',
                        color: metaColor,
                      ),
                      const Spacer(),
                      _BatafsilButton(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onTap(listing);
                        },
                      ),
                    ],
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

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.price, required this.color});

  final int price;
  final Color color;

  @override
  Widget build(BuildContext context) {
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
            maxLines: 1,
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
  const _BatafsilButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.splashGreen,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          height: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Batafsil',
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
    return ColoredBox(
      color: const Color(0xFFEEF1F4),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: 480,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSync) {
          if (wasSync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, _, _) => const Center(
          child: Icon(Icons.image_outlined, size: 28, color: Color(0xFFB4B9BF)),
        ),
      ),
    );
  }
}
