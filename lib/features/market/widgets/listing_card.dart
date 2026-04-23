import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../models/market_listing.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onDetailsTap,
  });

  final MarketListing listing;
  final ValueChanged<MarketListing> onDetailsTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE3E5E8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: _LazyBlurImage(url: listing.imageUrl),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _formatPrice(listing.priceUzs),
                          style: const TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: AppColors.textBlack,
                          ),
                        ),
                        const TextSpan(
                          text: ' UZS',
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w500,
                            fontSize: 18,
                            color: AppColors.textBlack,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      height: 1.1,
                      color: AppColors.textBlack,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MetaRow(
                    icon: Icons.map_outlined,
                    iconColor: const Color(0xFFFE7A1A),
                    text: listing.district,
                  ),
                  const SizedBox(height: 4),
                  _MetaRow(
                    icon: Icons.square_foot_rounded,
                    iconColor: const Color(0xFF00A1FF),
                    text: '${listing.areaM2} m²',
                  ),
                  const Spacer(),
                  Material(
                    color: AppColors.splashGreen,
                    borderRadius: BorderRadius.circular(999),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onDetailsTap(listing);
                      },
                      child: const SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Batafsil',
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 24,
                              color: Colors.black,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(int value) {
    final raw = value.toString();
    final out = StringBuffer();

    for (var i = 0; i < raw.length; i++) {
      out.write(raw[i]);
      final remaining = raw.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) {
        out.write(' ');
      }
    }

    return out.toString();
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 16,
              color: Color(0xFF767A80),
            ),
          ),
        ),
      ],
    );
  }
}

class _LazyBlurImage extends StatelessWidget {
  const _LazyBlurImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFBFD9F2), Color(0xFF9FC1DF)],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              final visible = wasSynchronouslyLoaded || frame != null;
              return AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: child,
              );
            },
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox.shrink();
            },
            errorBuilder: (context, error, stack) {
              return const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
