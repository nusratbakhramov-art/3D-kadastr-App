import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/remote_image.dart';
import '../market_controller.dart';
import '../models/market_listing.dart';

class FeaturedCarousel extends StatefulWidget {
  const FeaturedCarousel({
    super.key,
    required this.controller,
    required this.onTap,
  });

  final MarketController controller;
  final ValueChanged<MarketListing> onTap;

  @override
  State<FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<FeaturedCarousel> {
  late final PageController _page;

  @override
  void initState() {
    super.initState();
    _page = PageController(viewportFraction: 0.78);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final items = widget.controller.items;
        final status = widget.controller.status;

        if (status == MarketStatus.loading && items.isEmpty) {
          return const _CarouselSkeleton();
        }
        if (items.isEmpty) return const SizedBox.shrink();

        final featured = items.take(8).toList();

        return SizedBox(
          height: 240,
          child: PageView.builder(
            controller: _page,
            padEnds: false,
            clipBehavior: Clip.none,
            itemCount: featured.length,
            onPageChanged: (_) {},
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _FeaturedCard(
                  listing: featured[i],
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onTap(featured[i]);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.listing, required this.onTap});

  final MarketListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF121617) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final metaColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF767A80);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: isDark
              ? null
              : Border.all(color: const Color(0xFFE3E5E8)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Image
            Positioned.fill(
              bottom: 85,
              child: RemoteImage(
                url: listing.imageUrl,
                memCacheWidth: 720,
              ),
            ),
            // Bottom info
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 85,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      listing.priceUzs > 0
                          ? '${_fmtPrice(listing.priceUzs)} UZS'
                          : 'Bepul',
                      style: TextStyle(
                        fontSize: 12,
                        color: metaColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      listing.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (listing.areaM2 > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${listing.areaM2} m²  •  ${listing.district}',
                        style: TextStyle(fontSize: 11, color: metaColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtPrice(num price) {
    final s = price.toInt().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1E2324) : const Color(0xFFEEEFF1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
