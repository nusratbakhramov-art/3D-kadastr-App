import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/gradient_surface.dart';
import '../../../widgets/remote_image.dart';
import '../market_controller.dart';
import '../models/market_listing.dart';

/// Home "Top modellar" swiper.
///
/// The card borrows the hero cards' finish (accent rim + coloured glow + top
/// sheen, see `features/services/widgets/service_card.dart`) so the two
/// sections read as one system. The photo runs edge-to-edge and the copy sits
/// on a frosted panel floating over it — the listing images are user-supplied
/// renders, so text can't rely on the bottom of the photo being dark or calm.
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
  static const double _cardHeight = 224;
  static const double _viewport = 0.78;
  static const double _gap = 12;

  late final PageController _page;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _page = PageController(viewportFraction: _viewport);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  /// 1.0 when card [i] is the settled page, easing to 0.0 one page away.
  double _proximity(int i) {
    var distance = (_current - i).toDouble().abs();
    if (_page.hasClients && _page.position.hasContentDimensions) {
      distance = ((_page.page ?? _current.toDouble()) - i).abs();
    }
    return (1 - distance).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final items = widget.controller.items;
        final status = widget.controller.status;

        if (status == MarketStatus.loading && items.isEmpty) {
          return const _CarouselSkeleton(height: _cardHeight);
        }
        if (items.isEmpty) return const SizedBox.shrink();

        final featured = items.take(8).toList();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _cardHeight,
              child: PageView.builder(
                controller: _page,
                padEnds: false,
                clipBehavior: Clip.none,
                itemCount: featured.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, i) {
                  return AnimatedBuilder(
                    animation: _page,
                    builder: (context, child) {
                      final t = _proximity(i);
                      // Neighbours sit back a little so the settled card reads
                      // as the subject. Anchored left: padEnds is false, so the
                      // active card is the leftmost one and its edge must not
                      // drift while the others shrink.
                      //
                      // Scale carries the depth; the fade is only a hint. It
                      // stays shallow because Opacity blends toward whatever is
                      // behind it — on the light background a deeper fade turned
                      // the neighbouring photo milky, which read as a broken
                      // image rather than a card standing further back.
                      return Transform.scale(
                        scale: 0.92 + 0.08 * t,
                        alignment: Alignment.centerLeft,
                        child: Opacity(opacity: 0.88 + 0.12 * t, child: child),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: _gap),
                      child: _FeaturedCard(
                        listing: featured[i],
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onTap(featured[i]);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            if (featured.length > 1) ...[
              const SizedBox(height: 12),
              _PageDots(count: featured.length, current: _current),
            ],
          ],
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
    final locale = Localizations.localeOf(context);
    final isFree = listing.priceUzs <= 0;
    const accent = AppColors.splashGreen;

    return Material(
      color: const Color(0xFF0E1213),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: accent.withValues(alpha: 0.20), width: 1),
      ),
      elevation: 8,
      shadowColor: accent.withValues(alpha: 0.22),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RemoteImage(url: listing.imageUrl, memCacheWidth: 720),
            // Top sheen — faint light fall-off for a glossy finish.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
            // Bounded left..right (not just left) so a long price can't run
            // the pill off the card; Align keeps it hugging its content.
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _PricePill(
                  label: isFree
                      ? _FeaturedCarouselStrings.free(locale)
                      : '${_fmtPrice(listing.priceUzs)} UZS',
                  highlight: isFree,
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: _GlassPanel(listing: listing),
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

/// Frosted info panel floating over the photo.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.listing});

  final MarketListing listing;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (listing.areaM2 > 0) '${listing.areaM2} m²',
      if (listing.district.isNotEmpty) listing.district,
    ].join('  •  ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 11),
          decoration: BoxDecoration(
            color: const Color(0xFF0A120D).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        height: 1.15,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 11,
                          height: 1.2,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Same gradient material as the home call/chat FABs that float
              // over this card. As a flat green-tinted outline it was the odd
              // one out on the screen and read as decoration; on the shared
              // surface it reads as the button it always was.
              const GradientSurface(
                light: AppColors.callGreenLight,
                base: AppColors.callGreen,
                deep: AppColors.callGreenDeep,
                size: 28,
                radius: 9,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Price/"Bepul" chip. Free listings keep the green accent — it's the hook; a
/// real price stays neutral so it doesn't shout louder than a free model.
///
/// The base is dark glass rather than a green tint: the photo behind is a
/// user-supplied render, and green-on-green (a sunlit lawn, say) washed the
/// label out completely. Blur + a dark base hold contrast over any image, which
/// is the same reason the info panel below is readable.
class _PricePill extends StatelessWidget {
  const _PricePill({required this.label, required this.highlight});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);

    return DecoratedBox(
      // Outside the clip — a shadow drawn inside it would be clipped away.
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: highlight
                  ? const Color(0xFF041209).withValues(alpha: 0.58)
                  : const Color(0xFF060E09).withValues(alpha: 0.60),
              borderRadius: radius,
              border: Border.all(
                color: highlight
                    ? AppColors.splashGreen.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                height: 1.1,
                color: highlight ? AppColors.splashGreen : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The idle dot has to invert with the theme — a white dot vanishes on the
    // light scaffold, which is where this section actually lives in light mode.
    final idle = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.18);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i == current ? 16 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == current ? AppColors.splashGreen : idle,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _FeaturedCarouselStrings {
  const _FeaturedCarouselStrings._();

  static String free(Locale l) => switch (l.languageCode) {
    'ru' => 'Бесплатно',
    'en' => 'Free',
    _ => 'Bepul',
  };
}

class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1E2324) : const Color(0xFFEEEFF1);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: 0.78,
          child: Container(
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
      ),
    );
  }
}
